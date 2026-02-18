#!/bin/bash
set -euo pipefail

# ==========================================
# ArgoCD 自动安装 + 强制指定 NodePort
# 使用方式:
# sudo bash install_argocd_final.sh 30099 30100
# ==========================================

HTTP_PORT=${1:-30099}
HTTPS_PORT=${2:-30100}

ARGOCD_NAMESPACE="argocd"
HELM_VERSION="v3.14.4"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

echo
log "🚀 开始部署 ArgoCD"
echo

# ===============================
# 1️⃣ 端口合法性检查
# ===============================
for PORT in $HTTP_PORT $HTTPS_PORT; do
  if [ "$PORT" -lt 30000 ] || [ "$PORT" -gt 32767 ]; then
      echo "❌ 端口必须在 30000-32767 之间"
      exit 1
  fi
done

# ===============================
# 2️⃣ 检查 Kubernetes
# ===============================
log "检查 Kubernetes 状态..."
kubectl cluster-info >/dev/null 2>&1 || {
  log "❌ Kubernetes 未运行"
  exit 1
}
log "✅ Kubernetes 正常"

# ===============================
# 3️⃣ 自动安装 Helm
# ===============================
if ! command -v helm >/dev/null 2>&1; then
    log "🔹 安装 Helm ${HELM_VERSION}..."

    TMP_DIR=$(mktemp -d)
    curl -sSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o ${TMP_DIR}/helm.tar.gz
    tar -xzf ${TMP_DIR}/helm.tar.gz -C ${TMP_DIR}
    mv ${TMP_DIR}/linux-amd64/helm /usr/local/bin/helm
    chmod +x /usr/local/bin/helm
    rm -rf ${TMP_DIR}

    log "✅ Helm 安装完成"
else
    log "✅ Helm 已存在"
fi

# ===============================
# 4️⃣ 创建命名空间
# ===============================
kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || \
kubectl create ns ${ARGOCD_NAMESPACE}

# ===============================
# 5️⃣ 添加 Helm 仓库
# ===============================
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# ===============================
# 6️⃣ 生成 values.yaml
# ===============================
cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePorts:
      http: ${HTTP_PORT}
      https: ${HTTPS_PORT}
EOF

# ===============================
# 7️⃣ 安装 / 升级 ArgoCD
# ===============================
log "部署 ArgoCD..."

helm upgrade --install argocd argo/argo-cd \
  -n ${ARGOCD_NAMESPACE} \
  -f /tmp/argocd-values.yaml

# ===============================
# 8️⃣ 等待启动
# ===============================
log "等待 ArgoCD Server 启动..."
kubectl -n ${ARGOCD_NAMESPACE} rollout status deploy/argocd-server --timeout=300s

log "✅ ArgoCD 已启动"

# ===============================
# 9️⃣ 自动开放防火墙
# ===============================
log "开放防火墙端口..."

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${HTTP_PORT}/tcp || true
    ufw allow ${HTTPS_PORT}/tcp || true
    ufw reload || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${HTTP_PORT}/tcp || true
    firewall-cmd --permanent --add-port=${HTTPS_PORT}/tcp || true
    firewall-cmd --reload || true
fi

# ===============================
# 🔟 输出访问信息
# ===============================
NODE_IP=$(hostname -I | awk '{print $1}')

ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo
echo "============================================"
echo "🎉 ArgoCD 部署完成"
echo
echo "访问地址:"
echo "https://${NODE_IP}:${HTTPS_PORT}"
echo
echo "用户名: admin"
echo "密码: ${ADMIN_PASSWORD}"
echo "============================================"
echo
