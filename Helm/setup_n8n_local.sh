#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级工业部署脚本 v3
# 支持 containerd、多节点导入、状态检测、HTML交付页
# ===================================================

# ---------- 配置 ----------
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
echo "🚀 n8n HA 企业级部署启动"
echo "========================================="

# ---------- 环境检测 ----------
echo "[CHECK] Kubernetes API"
kubectl version --short >/dev/null

echo "[CHECK] containerd"
sudo ctr version >/dev/null

echo "[CHECK] Helm"
helm version >/dev/null

# ---------- Step 0: 清理 ----------
echo "[INFO] 清理旧 PVC/PV"
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ---------- Step 0.5: 多节点镜像导入 ----------
echo "[INFO] 检查 containerd 镜像"

NODE_LIST=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for NODE in $NODE_LIST; do
  echo "🔍 检查节点: $NODE"

  if sudo ctr -n k8s.io images list | awk '{print $1}' | grep -q "^${N8N_IMAGE}$"; then
    echo "   ✅ 镜像已存在"
  else
    if [ -f "$TAR_FILE" ]; then
      echo "   ⚠ 未发现镜像，开始导入..."

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
      echo "   ✅ 导入完成"
    else
      echo "   ❌ 未找到镜像 tar 文件: $TAR_FILE"
      exit 1
    fi
  fi
done

# ---------- Step 1: StorageClass ----------
echo "[INFO] 检测 StorageClass"
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)

if [ -z "$SC_NAME" ]; then
  echo "⚠ 无 StorageClass，将创建手动 PV"
else
  echo "✅ StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建 Helm Chart ----------
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

resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 250m
EOF

# ---------- StatefulSet ----------
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

# ---------- Service ----------
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

# ---------- 安装 ----------
echo "[INFO] Helm 安装/升级"

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

if helm status n8n-ha -n $NAMESPACE >/dev/null 2>&1; then
  helm upgrade n8n-ha "$CHART_DIR" -n $NAMESPACE
else
  helm install n8n-ha "$CHART_DIR" -n $NAMESPACE
fi

# ---------- 等待 ----------
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

# ---------- 生成 HTML ----------
SERVICE_IP=$(kubectl -n $NAMESPACE get svc n8n -o jsonpath='{.spec.clusterIP}')
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}')

cat > "$HTML_FILE" <<EOF
<html>
<head><title>n8n HA</title></head>
<body>
<h2>n8n HA 部署完成</h2>
<p>Namespace: $NAMESPACE</p>
<p>ClusterIP: $SERVICE_IP</p>
<p>Replicas: $REPLICA_COUNT</p>
<p>访问方式:</p>
<pre>kubectl -n $NAMESPACE port-forward svc/n8n 5678:5678</pre>
</body>
</html>
EOF

echo ""
echo "========================================="
echo "🎉 n8n HA 企业部署完成"
echo "HTML 页面: $HTML_FILE"
echo "========================================="
