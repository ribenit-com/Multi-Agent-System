#!/bin/bash
set -Eeuo pipefail

# ===================================================
# Redis HA 企业级一键部署 + HTML 交付页面
# 支持 Pod 状态可视化
#  功能总结：
# 1. 自动清理冲突 PVC/PV（非阻塞）
# 2. 自动生成 Helm Chart + 手动 PV（如无 StorageClass）
# 3. 自动创建 ArgoCD Application
# 4. 等待 StatefulSet 就绪
# 5. 生成企业交付 HTML 页面
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/redis-ha-chart"
NAMESPACE="database"
ARGO_APP="redis-ha"
GITHUB_REPO="ribenit-com/Multi-Agent-k8s-gitops-postgres"
PVC_SIZE="10Gi"
APP_LABEL="redis"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/redis_ha_info.html"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV（非阻塞） ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep redis-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

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
name: redis-ha-chart
description: "Redis 7.0 Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "7.0"
EOF

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2
image:
  registry: docker.io
  repository: redis
  tag: "7.0"
  pullPolicy: IfNotPresent

redis:
  password: myredispassword

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 250m
EOF

cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  labels:
    app: redis
spec:
  serviceName: redis-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["redis-server", "--requirepass", "{{ .Values.redis.password }}"]
          ports:
            - containerPort: 6379
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

cat > "$CHART_DIR/templates/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  selector:
    app: redis
EOF

cat > "$CHART_DIR/templates/headless-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
spec:
  clusterIP: None
  ports:
    - port: 6379
      targetPort: 6379
  selector:
    app: redis
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
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

# ---------- Step 4: 应用 ArgoCD Application ----------
echo "=== Step 4: 应用 Redis ArgoCD Application ==="
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
    path: redis-ha-chart
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

# ---------- Step 4a: 等待 StatefulSet ----------
echo "等待 Redis StatefulSet 就绪..."
for i in {1..60}; do
  if kubectl -n $NAMESPACE get sts redis >/dev/null 2>&1; then
    kubectl -n $NAMESPACE rollout status sts/redis --timeout=300s && break
  else
    echo "[$i] StatefulSet redis 尚未创建，等待 5s..."
    sleep 5
  fi
done

# ---------- Step 5: 生成企业交付 HTML ----------
echo "=== Step 5: 生成 HTML 页面 ==="
SERVICE_IP=$(kubectl -n $NAMESPACE get svc redis -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts redis -o jsonpath='{.spec.replicas}' || echo "2")

POD_STATUS=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers || true)

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
<div class="info"><span class="label">Service:</span><span class="value">redis</span></div>
<div class="info"><span class="label">ClusterIP:</span><span class="value">$SERVICE_IP</span></div>
<div class="info"><span class="label">端口:</span><span class="value">6379</span></div>
<div class="info"><span class="label">密码:</span><span class="value">myredispassword</span></div>
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
kubectl -n $NAMESPACE port-forward svc/redis 6379:6379
redis-cli -h localhost -a myredispassword
</pre>

<h3>Python 示例</h3>
<pre>
import redis
r = redis.Redis(host="$SERVICE_IP", port=6379, password="myredispassword")
r.set("test","hello")
print(r.get("test"))
</pre>

<h3>Java 示例</h3>
<pre>
String url = "redis://:myredispassword@$SERVICE_IP:6379";
Jedis jedis = new Jedis(url)
jedis.set("test","hello")
System.out.println(jedis.get("test"))
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
