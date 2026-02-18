#!/bin/bash
set -Eeuo pipefail

# ===================================================
# Redis HA 企业级一键部署 + HTML 交付页面
# 支持 Pod 状态可视化
#  功能总结：
# 自动清理冲突 PVC/PV
# 自动生成 Helm Chart + 手动 PV（如无 StorageClass）
# 直接部署 StatefulSet 和 Service（无需 ArgoCD）
# 等待 StatefulSet 就绪
# 生成企业交付 HTML 页面
# 显示每个 Pod 状态：Running（绿色）、Pending（橙色）、Failed/CrashLoop（红色）
# 页面内显示 PVC、访问方式、Python/Java 示例代码
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/redis-ha-chart"
NAMESPACE="database"
PVC_SIZE="10Gi"
APP_LABEL="redis"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/redis_ha_info.html"
REDIS_PASSWORD="myredispassword"
REPLICA_COUNT=2

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
kubectl get pv -o name | grep redis-pv- | xargs -r kubectl delete || true

# ---------- Step 1: 检测 StorageClass ----------
echo "=== Step 1: 检测 StorageClass ==="
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  echo "⚠️ 集群没有 StorageClass，将使用手动 PV"
else
  echo "✅ 检测到 StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 2: 创建手动 PV ==="
  for i in $(seq 0 $((REPLICA_COUNT-1))); do
    PV_NAME="redis-pv-$i"
    mkdir -p /mnt/data/redis-$i
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
    path: /mnt/data/redis-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 3: 创建 StatefulSet ----------
echo "=== Step 3: 创建 Redis StatefulSet ==="
cat > /tmp/redis-sts.yaml <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $APP_LABEL
  namespace: $NAMESPACE
spec:
  serviceName: $APP_LABEL-headless
  replicas: $REPLICA_COUNT
  selector:
    matchLabels:
      app: $APP_LABEL
  template:
    metadata:
      labels:
        app: $APP_LABEL
    spec:
      containers:
      - name: $APP_LABEL
        image: redis:7.2
        command: ["redis-server", "--requirepass", "$REDIS_PASSWORD"]
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: $PVC_SIZE
      $( [ -n "$SC_NAME" ] && echo "storageClassName: $SC_NAME" )
EOF

kubectl apply -f /tmp/redis-sts.yaml

# ---------- Step 4: 创建 Service ----------
echo "=== Step 4: 创建 Redis Service ==="
cat > /tmp/redis-svc.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APP_LABEL
  namespace: $NAMESPACE
spec:
  selector:
    app: $APP_LABEL
  ports:
  - port: 6379
    targetPort: 6379
EOF

kubectl apply -f /tmp/redis-svc.yaml

# ---------- Step 4a: 创建 Headless Service ----------
cat > /tmp/redis-headless.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $APP_LABEL-headless
  namespace: $NAMESPACE
spec:
  clusterIP: None
  selector:
    app: $APP_LABEL
  ports:
  - port: 6379
    targetPort: 6379
EOF

kubectl apply -f /tmp/redis-headless.yaml

# ---------- Step 5: 等待 StatefulSet 就绪 ----------
echo "等待 Redis StatefulSet 就绪..."
kubectl -n $NAMESPACE rollout status sts/$APP_LABEL --timeout=300s

# ---------- Step 6: 生成 HTML 页面 ----------
echo "=== Step 6: 生成 HTML 页面 ==="
SERVICE_IP=$(kubectl -n $NAMESPACE get svc $APP_LABEL -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
POD_STATUS=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers)

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>Redis HA 企业交付指南</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
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
<h2>🎉 Redis HA 安装完成</h2>

<h3>数据库信息</h3>
<div class="info"><span class="label">Namespace:</span><span class="value">$NAMESPACE</span></div>
<div class="info"><span class="label">Service:</span><span class="value">$APP_LABEL</span></div>
<div class="info"><span class="label">ClusterIP:</span><span class="value">$SERVICE_IP</span></div>
<div class="info"><span class="label">端口:</span><span class="value">6379</span></div>
<div class="info"><span class="label">密码:</span><span class="value">$REDIS_PASSWORD</span></div>
<div class="info"><span class="label">副本数:</span><span class="value">$REPLICA_COUNT</span></div>

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
kubectl -n $NAMESPACE port-forward svc/$APP_LABEL 6379:6379
redis-cli -h localhost -a $REDIS_PASSWORD
</pre>

<h3>Python 示例</h3>
<pre>
import redis
r = redis.Redis(host="$SERVICE_IP", port=6379, password="$REDIS_PASSWORD")
r.set("test","hello")
print(r.get("test"))
</pre>

<h3>Java 示例</h3>
<pre>
String url = "redis://:$REDIS_PASSWORD@$SERVICE_IP:6379";
Jedis jedis = new Jedis(url);
jedis.set("test","hello");
System.out.println(jedis.get("test"));
</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</div>
</body>
</html>
EOF

echo "✅ Redis HA 企业交付 HTML 页面已生成: $HTML_FILE"
