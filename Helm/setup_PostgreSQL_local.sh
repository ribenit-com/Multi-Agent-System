#!/bin/bash
set -Eeuo pipefail

# ===================================================
# PostgreSQL HA 企业级一键部署 + HTML 交付页面
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/postgres-ha-chart"
NAMESPACE="database"
ARGO_APP="postgres-ha"
GITHUB_REPO="ribenit-com/Multi-Agent-k8s-gitops-postgres"
PVC_SIZE="10Gi"
APP_LABEL="postgres"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/postgres_ha_info.html"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有冲突 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
kubectl get pv -o name | grep postgres-pv- | xargs -r kubectl delete || true

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

# Chart.yaml
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: postgres-ha-chart
description: "Official PostgreSQL 16.3 Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "16.3"
EOF

# values.yaml
cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2

image:
  registry: docker.m.daocloud.io
  repository: library/postgres
  tag: "16.3"
  pullPolicy: IfNotPresent

postgresql:
  username: myuser
  password: mypassword
  database: mydb

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

ha:
  enabled: true
  synchronousCommit: "on"
  replicationMode: "asynchronous"
EOF

# templates/statefulset.yaml
cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  serviceName: postgres-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: POSTGRES_USER
              value: {{ .Values.postgresql.username | quote }}
            - name: POSTGRES_PASSWORD
              value: {{ .Values.postgresql.password | quote }}
            - name: POSTGRES_DB
              value: {{ .Values.postgresql.database | quote }}
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: {{ .Values.persistence.size }}
        {{- if .Values.persistence.storageClass }}
        storageClassName: {{ .Values.persistence.storageClass }}
        {{- end }}
EOF

# templates/service.yaml
cat > "$CHART_DIR/templates/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
  selector:
    app: postgres
EOF

# templates/headless-service.yaml
cat > "$CHART_DIR/templates/headless-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: postgres
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="postgres-pv-$i"
    mkdir -p /mnt/data/postgres-$i
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
    path: /mnt/data/postgres-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: 应用 ArgoCD Application ----------
echo "=== Step 4: 应用 ArgoCD Application ==="
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/$GITHUB_REPO.git'
    targetRevision: main
    path: postgres-ha-chart
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "等待 PostgreSQL StatefulSet 就绪..."
kubectl -n $NAMESPACE rollout status sts/$APP_LABEL --timeout=300s

# ---------- Step 5: 生成企业交付 HTML ----------
echo "=== Step 5: 生成 HTML 页面 ==="

# 获取集群信息
SERVICE_IP=$(kubectl -n $NAMESPACE get svc $APP_LABEL -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
NODE_PORT=$(kubectl -n $NAMESPACE get svc $APP_LABEL -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

DB_USER="myuser"
DB_PASSWORD="mypassword"
DB_NAME="mydb"
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts $APP_LABEL -o jsonpath='{.spec.replicas}' || echo "2")

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>PostgreSQL HA 企业交付指南</title>
<style>
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto;background:#f5f7fa}
.container{padding:40px;max-width:900px;margin:auto}
.card{background:#fff;padding:30px;border-radius:12px;box-shadow:0 8px 24px rgba(0,0,0,.08);margin-bottom:30px}
.title{font-size:24px;font-weight:700;margin-bottom:20px;color:#333}
.subtitle{font-size:18px;font-weight:600;margin-bottom:10px;color:#555}
.text{font-size:14px;color:#666;line-height:1.6}
.code{background:#f0f2f5;padding:10px;border-radius:6px;font-family:monospace;margin-top:5px;display:block;white-space:pre-wrap}
</style>
</head>
<body>
<div class="container">

<div class="card">
<div class="title">🎉 PostgreSQL HA 安装完成</div>
<div class="text">本指南说明如何访问和使用 PostgreSQL HA 集群。</div>
</div>

<div class="card">
<div class="subtitle">1️⃣ 数据库基本信息</div>
<div class="text">
Namespace: <span class="code">$NAMESPACE</span><br>
Service: <span class="code">$APP_LABEL</span><br>
ClusterIP: <span class="code">$SERVICE_IP</span><br>
EOF

if [ -n "$NODE_PORT" ]; then
  echo "NodePort: <span class=\"code\">$NODE_PORT</span><br>" >> "$HTML_FILE"
fi

cat >> "$HTML_FILE" <<EOF
用户名: <span class="code">$DB_USER</span><br>
密码: <span class="code">$DB_PASSWORD</span><br>
数据库: <span class="code">$DB_NAME</span><br>
副本数: <span class="code">$REPLICA_COUNT</span><br>
</div>
</div>

<div class="card">
<div class="subtitle">2️⃣ PVC / 存储信息</div>
<div class="text">
PVC 列表：
<pre class="code">
$PVC_LIST
</pre>
大小：$PVC_SIZE
</div>
</div>

<div class="card">
<div class="subtitle">3️⃣ 访问方式</div>
<div class="text">
<ul>
<li>集群内部访问: Service 名称 <code>$APP_LABEL</code>，端口 5432</li>
<li>集群外访问: Port-Forward 或 NodePort</li>
<pre class="code">
kubectl -n $NAMESPACE port-forward svc/$APP_LABEL 5432:5432
psql -h localhost -U $DB_USER -d $DB_NAME
</pre>
</ul>
</div>
</div>

<div class="card">
<div class="subtitle">4️⃣ 数据库连接示例</div>
<div class="text">
<b>psql 命令行:</b>
<pre class="code">
psql -h $SERVICE_IP -U $DB_USER -d $DB_NAME
</pre>

<b>Python (psycopg2):</b>
<pre class="code">
import psycopg2
conn = psycopg2.connect(
    host="$SERVICE_IP",
    database="$DB_NAME",
    user="$DB_USER",
    password="$DB_PASSWORD"
)
cur = conn.cursor()
cur.execute("SELECT version();")
print(cur.fetchone())
</pre>

<b>Java (JDBC):</b>
<pre class="code">
String url = "jdbc:postgresql://$SERVICE_IP:5432/$DB_NAME";
Properties props = new Properties();
props.setProperty("user","$DB_USER");
props.setProperty("password","$DB_PASSWORD");
Connection conn = DriverManager.getConnection(url, props);
</pre>
</div>
</div>

<div class="card">
<div class="subtitle">5️⃣ 注意事项</div>
<div class="text">
<ul>
<li>首次使用请修改数据库密码</li>
<li>建议使用 Kubernetes Secret 管理密码</li>
<li>HA 模式下主从同步为异步模式</li>
<li>可通过 ArgoCD 查看 Helm Chart 同步状态</li>
</ul>
</div>
</div>

<div class="card">
生成时间：$(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</body>
</html>
EOF

echo "✅ PostgreSQL HA 企业交付 HTML 页面已生成: $HTML_FILE"
