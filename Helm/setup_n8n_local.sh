#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级部署脚本 v7
# 自适应：Helm / ArgoCD
# 离线镜像支持 + GitOps支持 + 诊断增强
# ===================================================

SCRIPT_VERSION="7.0.0"

CHART_DIR="$HOME/gitops/n8n-ha-chart"
GIT_ROOT="$HOME/gitops"
NAMESPACE="automation"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
ARGO_APP_NAME="n8n-ha"
N8N_IMAGE="docker.io/n8nio/n8n:2.8.2"
TAR_FILE="$CHART_DIR/n8n_2.8.2.tar"

echo "=================================================="
echo "🚀 n8n HA 企业级部署启动 (v$SCRIPT_VERSION)"
echo "=================================================="

# ===================================================
# 基础检查
# ===================================================

echo "[CHECK] Kubernetes API"
kubectl cluster-info >/dev/null || { echo "❌ K8s API 不可达"; exit 1; }

echo "[CHECK] containerd"
systemctl is-active --quiet containerd || { echo "❌ containerd 未运行"; exit 1; }

echo "[CHECK] Helm"
helm version >/dev/null 2>&1 || echo "⚠ Helm 未安装（若走 ArgoCD 可忽略）"

# ===================================================
# 检查 ArgoCD
# ===================================================

ARGO_MODE=false

if kubectl get ns argocd >/dev/null 2>&1; then
  if kubectl -n argocd get applications.argoproj.io >/dev/null 2>&1; then
    ARGO_MODE=true
  fi
fi

if [ "$ARGO_MODE" = true ]; then
  echo "✅ 检测到 ArgoCD，进入 GitOps 模式"
else
  echo "ℹ 未检测到 ArgoCD，进入 Helm 直装模式"
fi

# ===================================================
# 镜像检查
# ===================================================

echo "[CHECK] containerd 镜像"

if sudo ctr -n k8s.io images list | awk '{print $1}' | grep -q "^${N8N_IMAGE}$"; then
  echo "✅ 镜像存在"
else
  if [ -f "$TAR_FILE" ]; then
    echo "⚠ 导入离线镜像..."
    START=$(date +%s)
    sudo ctr -n k8s.io image import "$TAR_FILE"
    END=$(date +%s)
    echo "✅ 导入完成 ($(($END-$START)) 秒)"
  else
    echo "❌ 未找到镜像: $TAR_FILE"
    exit 1
  fi
fi

# ===================================================
# 生成 Helm Chart
# ===================================================

echo "[INFO] 生成 Helm Chart"

mkdir -p "$CHART_DIR/templates"

SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

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
  repository: docker.io/n8nio/n8n
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
# 部署逻辑
# ===================================================

kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

if [ "$ARGO_MODE" = true ]; then

  echo "[GITOPS] 提交到仓库"

  cd "$GIT_ROOT"
  git add n8n-ha-chart

  if git diff --cached --quiet; then
    echo "ℹ 无变更"
  else
    git commit -m "feat: update n8n-ha-chart $(date +%F-%T)"
    git push origin main
    echo "✅ 已推送 GitOps"
  fi

  echo "[GITOPS] 等待 ArgoCD 同步"

  for i in {1..60}; do
    SYNC=$(kubectl -n argocd get applications.argoproj.io $ARGO_APP_NAME -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n argocd get applications.argoproj.io $ARGO_APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo "   Sync: $SYNC | Health: $HEALTH"
    if [ "$SYNC" == "Synced" ] && [ "$HEALTH" == "Healthy" ]; then
      break
    fi
    sleep 5
  done

else

  echo "[HELM] 直接部署"

  if helm status n8n-ha -n $NAMESPACE >/dev/null 2>&1; then
    helm upgrade n8n-ha "$CHART_DIR" -n $NAMESPACE
  else
    helm install n8n-ha "$CHART_DIR" -n $NAMESPACE
  fi

fi

# ===================================================
# 等待就绪
# ===================================================

echo "[INFO] 等待 StatefulSet 就绪"

for i in {1..60}; do
  READY=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  READY=${READY:-0}
  DESIRED=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")

  echo "   状态: $READY / $DESIRED"

  if [ "$READY" == "$DESIRED" ]; then
    echo "🎉 n8n HA 部署成功"
    exit 0
  fi

  sleep 5
done

echo "❌ 部署失败，打印诊断信息"
kubectl -n $NAMESPACE get pods -o wide
kubectl -n $NAMESPACE describe pod n8n-0 || true
exit 1
