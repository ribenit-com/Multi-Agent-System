#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级工业部署脚本 v4（自诊断增强）
# ===================================================

CHART_DIR="$HOME/gitops/n8n-ha-chart"
NAMESPACE="automation"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/n8n_ha_info.html"
N8N_IMAGE="docker.io/n8nio/n8n:2.8.2"
TAR_FILE="$CHART_DIR/n8n_2.8.2.tar"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

echo "========================================="
echo "🚀 n8n HA 企业级部署启动 (v4 自诊断版)"
echo "========================================="

# ===================================================
# 自诊断阶段
# ===================================================

echo "[CHECK] Kubernetes API"
kubectl cluster-info >/dev/null 2>&1 || {
  echo "❌ 无法连接 Kubernetes API"
  exit 1
}

echo "[CHECK] Node Ready 状态"
NOT_READY=$(kubectl get nodes --no-headers | awk '$2!="Ready" {print $1}')
if [ -n "$NOT_READY" ]; then
  echo "❌ 以下节点未 Ready:"
  echo "$NOT_READY"
  exit 1
else
  echo "✅ 所有节点 Ready"
fi

echo "[CHECK] containerd 服务"
if ! systemctl is-active --quiet containerd; then
  echo "❌ containerd 未运行"
  exit 1
else
  echo "✅ containerd 正常"
fi

echo "[CHECK] Helm"
helm version >/dev/null 2>&1 || {
  echo "❌ Helm 未安装"
  exit 1
}

echo "[CHECK] CoreDNS"
if ! kubectl -n kube-system get pods -l k8s-app=kube-dns | grep -q Running; then
  echo "⚠ CoreDNS 未完全 Running（可能不影响本地部署）"
else
  echo "✅ CoreDNS 正常"
fi

# ===================================================
# 清理旧资源
# ===================================================

echo "[INFO] 清理旧 PVC/PV"
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ===================================================
# 镜像导入（离线支持）
# ===================================================

echo "[INFO] 检查 containerd 镜像"

if sudo ctr -n k8s.io images list | awk '{print $1}' | grep -q "^${N8N_IMAGE}$"; then
  echo "✅ 镜像已存在"
else
  if [ -f "$TAR_FILE" ]; then
    echo "⚠ 未发现镜像，开始导入..."
    START_TIME=$(date +%s)
    sudo ctr -n k8s.io image import "$TAR_FILE" >/dev/null 2>&1 &
    PID=$!
    while kill -0 $PID 2>/dev/null; do
      ELAPSED=$(( $(date +%s) - START_TIME ))
      printf "\r   ⏳ 导入中... %ds" "$ELAPSED"
      sleep 2
    done
    wait $PID
    echo ""
    echo "✅ 镜像导入完成"
  else
    echo "❌ 未找到镜像 tar 文件: $TAR_FILE"
    exit 1
  fi
fi

# ===================================================
# StorageClass
# ===================================================

SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$SC_NAME" ]; then
  echo "⚠ 无 StorageClass，将使用手动 PV"
else
  echo "✅ StorageClass: $SC_NAME"
fi

# ===================================================
# 创建 Helm Chart
# ===================================================

echo "[INFO] 生成 Helm Chart"

cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: n8n-ha-chart
type: application
version: 1.0.0
appVersion: "2.8.2"
EOF

echo "*.tar" > "$CHART_DIR/.helmignore"

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2
image:
  repository: n8nio/n8n
  tag: "2.8.2"
  pullPolicy: Never
persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}
EOF

cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: n8n
spec:
  serviceName: n8n-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      containers:
        - name: n8n
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 5678
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
  name: n8n
spec:
  type: ClusterIP
  ports:
    - port: 5678
      targetPort: 5678
  selector:
    app: n8n
EOF

# ===================================================
# 安装
# ===================================================

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

if helm status n8n-ha -n $NAMESPACE >/dev/null 2>&1; then
  helm upgrade n8n-ha "$CHART_DIR" -n $NAMESPACE
else
  helm install n8n-ha "$CHART_DIR" -n $NAMESPACE
fi

# ===================================================
# 等待就绪
# ===================================================

echo "[INFO] 等待 StatefulSet 就绪"
for i in {1..60}; do
  READY=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
  echo "   状态: $READY / $DESIRED"
  if [ "$READY" == "$DESIRED" ]; then
    echo "✅ 部署成功"
    break
  fi
  sleep 5
done

# ===================================================
# 生成 HTML
# ===================================================

SERVICE_IP=$(kubectl -n $NAMESPACE get svc n8n -o jsonpath='{.spec.clusterIP}')
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}')

cat > "$HTML_FILE" <<EOF
<html>
<body>
<h2>n8n HA 部署成功</h2>
<p>Namespace: $NAMESPACE</p>
<p>ClusterIP: $SERVICE_IP</p>
<p>Replicas: $REPLICA_COUNT</p>
</body>
</html>
EOF

echo ""
echo "========================================="
echo "🎉 n8n HA 企业部署完成"
echo "HTML 页面: $HTML_FILE"
echo "========================================="
