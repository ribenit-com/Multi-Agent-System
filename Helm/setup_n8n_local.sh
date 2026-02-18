#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级一键部署 + HTML 交付页面 + PostgreSQL 检测
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/n8n-ha-chart"
NAMESPACE="automation"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/n8n_ha_info.html"

POSTGRES_SERVICE="postgres"
POSTGRES_NAMESPACE="database"
POSTGRES_USER="myuser"
POSTGRES_PASSWORD="mypassword"
POSTGRES_DB_PREFIX="n8n"

N8N_IMAGE="n8nio/n8n"
N8N_TAG="2.8.2"   # 官方稳定版本

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ---------- Step 0.5: 节点提前拉取 n8n 镜像，显示下载进度 ----------
echo "=== Step 0.5: 在节点上提前拉取 n8n 镜像 (需要 sudo) ==="
sudo docker pull ${N8N_IMAGE}:${N8N_TAG}

# ---------- Step 1: 检测 StorageClass ----------
echo "=== Step 1: 检测 StorageClass ==="
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  echo "⚠️ 集群没有 StorageClass，将使用手动 PV"
else
  echo "✅ 检测到 StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建 Helm Chart ----------
echo "=== Step 2: 创建 Helm Chart ==="
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: n8n-ha-chart
description: "n8n Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "$N8N_TAG"
EOF

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2
image:
  registry: n8nio
  repository: n8n
  tag: "$N8N_TAG"
  pullPolicy: IfNotPresent

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

postgres:
  host: $POSTGRES_SERVICE.$POSTGRES_NAMESPACE.svc.cluster.local
  user: $POSTGRES_USER
  password: $POSTGRES_PASSWORD
  dbPrefix: $POSTGRES_DB_PREFIX
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="n8n-pv-$i"
    mkdir -p /mnt/data/n8n-$i
    cat > /tmp/$PV_NAME.yaml <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
spec:
  capacity:
    storage: $PVC_SIZE
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data/n8n-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: Helm 安装 n8n ----------
echo "=== Step 4: 使用 Helm 安装 n8n HA ==="
helm upgrade --install n8n-ha $CHART_DIR -n $NAMESPACE --create-namespace

# ---------- Step 4a: 等待 StatefulSet 就绪 + Log ----------
echo "等待 n8n StatefulSet 就绪..."
for i in {1..60}; do
  echo "[$i] 检查 StatefulSet n8n 状态..."
  if kubectl -n $NAMESPACE get sts n8n >/dev/null 2>&1; then
    kubectl -n $NAMESPACE get sts n8n -o wide
    echo "--- Pod 状态 ---"
    kubectl -n $NAMESPACE get pods -l app=$APP_LABEL
    READY=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.status.readyReplicas}' || echo "0")
    DESIRED=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' || echo "2")
    if [ "$READY" == "$DESIRED" ]; then
      echo "✅ StatefulSet n8n 已就绪"
      break
    fi
    ERRPOD=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o jsonpath='{.items[?(@.status.containerStatuses[*].state.waiting.reason=="ErrImagePull")].metadata.name}' || true)
    if [ -n "$ERRPOD" ]; then
      echo "❌ Pod 镜像拉取失败: $ERRPOD"
      exit 1
    fi
  else
    echo "⚠️ StatefulSet n8n 尚未创建，等待 5s..."
  fi
  sleep 5
done

# ---------- Step 4b: 测试 PostgreSQL 连通性并初始化 ----------
echo "=== Step 4b: 测试 PostgreSQL 连通性并初始化数据库 ==="
DB_HOST=$(kubectl -n $POSTGRES_NAMESPACE get svc $POSTGRES_SERVICE -o jsonpath='{.spec.clusterIP}')
DB_NAME="${POSTGRES_DB_PREFIX}_$(date +%s)"
DB_INIT_STATUS="未执行"
DB_ERROR=""

for i in {1..12}; do
  echo "尝试连接 PostgreSQL ($DB_HOST)... [$i/12]"
  PGPASSWORD=$POSTGRES_PASSWORD psql -h $DB_HOST -U $POSTGRES_USER -d postgres -c "\q" >/dev/null 2>&1 && break
  sleep 5
  if [ $i -eq 12 ]; then
    DB_ERROR="⚠️ 无法连接 PostgreSQL 服务 $DB_HOST"
    echo $DB_ERROR
  fi
done

if [ -z "$DB_ERROR" ]; then
  echo "✅ PostgreSQL 可连接，开始初始化数据库 $DB_NAME"
  INIT_SQL="CREATE DATABASE $DB_NAME;"
  if PGPASSWORD=$POSTGRES_PASSWORD psql -h $DB_HOST -U $POSTGRES_USER -d postgres -c "$INIT_SQL"; then
    DB_INIT_STATUS="✅ 数据库 $DB_NAME 初始化成功"
  else
    DB_INIT_STATUS="❌ 数据库 $DB_NAME 初始化失败"
    DB_ERROR="初始化数据库失败，请检查用户权限或网络"
  fi
fi

# ---------- Step 5: 生成 HTML 报告 ----------
echo "=== Step 5: 生成 HTML 页面 ==="
POD_STATUS=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers || true)
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付指南</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="10">
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:650px}
h2 {color:#1677ff;margin-bottom:20px;text-align:center}
h3 {color:#444;margin-top:25px;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px}
pre {background:#f0f2f5;padding:12px;border-radius:6px;overflow-x:auto;font-family:monospace}
.info {margin-bottom:10px}
.label {font-weight:600;color:#333}
.value {color:#555;margin-left:5px}
.status-running {color:green;font-weight:600}
.status-pending {color:orange;font-weight:600}
.status-failed {color:red;font-weight:600}
.footer {margin-top:20px;font-size:12px;color:#888;text-align:center}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🎉 n8n HA 安装完成</h2>

<h3>数据库信息</h3>
<div class="info"><span class="label">PostgreSQL:</span><span class="value">$POSTGRES_SERVICE.$POSTGRES_NAMESPACE</span></div>
<div class="info"><span class="label">用户名:</span><span class="value">$POSTGRES_USER</span></div>
<div class="info"><span class="label">密码:</span><span class="value">$POSTGRES_PASSWORD</span></div>
<div class="info"><span class="label">数据库:</span><span class="value">$DB_NAME</span></div>
<div class="info"><span class="label">副本数:</span><span class="value">2</span></div>
<div class="info"><span class="label">数据库初始化:</span><span class="value">$DB_INIT_STATUS</span></div>

<h3>PVC 列表</h3>
<pre>$PVC_LIST</pre>

<h3>Pod 状态</h3>
<pre>
EOF

while read -r line; do
  POD_NAME=$(echo $line | awk '{print $1}')
  STATUS=$(echo $line | awk '{print $2}')
  CASE_CLASS="status-failed"
  [[ "$STATUS" == "Running" ]] && CASE_CLASS="status-running"
  [[ "$STATUS" == "Pending" ]] && CASE_CLASS="status-pending"
  echo "<div class=\"$CASE_CLASS\">$POD_NAME : $STATUS</div>" >> "$HTML_FILE"
done <<< "$POD_STATUS"

cat >> "$HTML_FILE" <<EOF
</pre>

<h3>访问方式</h3>
<pre>
kubectl -n $NAMESPACE port-forward svc/n8n 5678:5678
</pre>

<h3>Python 示例</h3>
<pre>
import psycopg2
conn = psycopg2.connect(
    host="$POSTGRES_SERVICE.$POSTGRES_NAMESPACE.svc.cluster.local",
    database="$DB_NAME",
    user="$POSTGRES_USER",
    password="$POSTGRES_PASSWORD"
)
cur = conn.cursor()
cur.execute("SELECT version();")
print(cur.fetchone())
</pre>

<h3>Java 示例</h3>
<pre>
String url = "jdbc:postgresql://$POSTGRES_SERVICE.$POSTGRES_NAMESPACE.svc.cluster.local:5432/$DB_NAME";
Properties props = new Properties();
props.setProperty("user","$POSTGRES_USER");
props.setProperty("password","$POSTGRES_PASSWORD");
Connection conn = DriverManager.getConnection(url, props);
</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</div>
</body>
</html>
EOF

echo "✅ n8n HA 企业交付 HTML 页面已生成: $HTML_FILE"
