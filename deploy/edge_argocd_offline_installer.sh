#!/bin/bash
set -euo pipefail

# ===============================
# 基础配置
# ===============================
ARGOCD_NAMESPACE="argocd"
NODEPORT_PORT=30100

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ===============================
# 1. 检查 Kubernetes
# ===============================
log "检查 Kubernetes 状态..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    log "❌ Kubernetes 未运行"
    exit 1
fi

log "✅ Kubernetes 正常"

# ===============================
# 2. 检查 Helm
# ===============================
if ! command -v helm >/dev/null 2>&1; then
    log "❌ 未安装 Helm，请先手动安装 Helm"
    exit 1
fi

log "✅ Helm 正常"

# ===============================
# 3. 创建命名空间
# ===============================
if ! kubectl get ns "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    kubectl create ns "$ARGOCD_NAMESPACE"
    log "已创建命名空间"
fi

# ===============================
# 4. 安装 ArgoCD
# ===============================
log "添加 Helm 仓库..."

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePort: ${NODEPORT_PORT}
    port: 443
    targetPort: 8080
EOF

log "部署 ArgoCD..."

helm upgrade --install argocd argo/argo-cd \
  -n ${ARGOCD_NAMESPACE} \
  -f /tmp/argocd-values.yaml

# ===============================
# 5. 等待 Pod 就绪
# ===============================
log "等待 ArgoCD Server 就绪..."

kubectl -n ${ARGOCD_NAMESPACE} wait \
  --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  --timeout=300s

log "✅ ArgoCD 已就绪"

# ===============================
# 6. 开放防火墙（仅本机）
# ===============================
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow ${NODEPORT_PORT}/tcp || true
    sudo ufw reload || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-port=${NODEPORT_PORT}/tcp || true
    sudo firewall-cmd --reload || true
fi

# ===============================
# 7. 获取访问信息
# ===============================
NODE_IP=$(hostname -I | awk '{print $1}')

ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo
echo "===================================="
echo "ArgoCD 部署完成"
echo "访问地址: https://${NODE_IP}:${NODEPORT_PORT}"
echo "用户名: admin"
echo "密码: ${ADMIN_PASSWORD}"
echo "===================================="
echo
