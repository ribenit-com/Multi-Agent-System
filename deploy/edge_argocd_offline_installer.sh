#!/bin/bash
set -euo pipefail

# ===============================
# 基础配置
# ===============================
ARGOCD_NAMESPACE="argocd"
NODEPORT_PORT=30100
HELM_VERSION="v3.14.4"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

echo
log "🚀 开始部署 ArgoCD"
echo

# ===============================
# 1️⃣ 检查 Kubernetes
# ===============================
log "检查 Kubernetes 状态..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    log "❌ Kubernetes 未运行，请先启动集群"
    exit 1
fi

log "✅ Kubernetes 正常"

# ===============================
# 2️⃣ 自动安装 Helm
# ===============================
if ! command -v helm >/dev/null 2>&1; then
    log "🔹 未检测到 Helm，开始安装..."

    TMP_DIR=$(mktemp -d)

    curl -sSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o ${TMP_DIR}/helm.tar.gz
    tar -xzf ${TMP_DIR}/helm.tar.gz -C ${TMP_DIR}

    sudo mv ${TMP_DIR}/linux-amd64/helm /usr/local/bin/helm
    sudo chmod +x /usr/local/bin/helm

    rm -rf ${TMP_DIR}

    log "✅ Helm 安装完成: $(helm version --short)"
else
    log "✅ Helm 已存在: $(helm version --short)"
fi

# ===============================
# 3️⃣ 创建命名空间
# ===============================
if ! kubectl get ns "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    kubectl create ns "${ARGOCD_NAMESPACE}"
    log "已创建命名空间 ${ARGOCD_NAMESPACE}"
else
    log "命名空间已存在"
fi

# ===============================
# 4️⃣ 添加 Helm 仓库
# ===============================
log "添加 Argo Helm 仓库..."

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# ===============================
# 5️⃣ 生成 values 文件
# ===============================
cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePort: ${NODEPORT_PORT}
    port: 443
    targetPort: 8080
EOF

# ===============================
# 6️⃣ 安装 ArgoCD
# ===============================
log "部署 ArgoCD..."

helm upgrade --install argocd argo/argo-cd \
  -n ${ARGOCD_NAMESPACE} \
  -f /tmp/argocd-values.yaml

# ===============================
# 7️⃣ 等待 Pod Ready
# ===============================
log "等待 ArgoCD Server 就绪..."

kubectl -n ${ARGOCD_NAMESPACE} wait \
  --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  --timeout=300s

log "✅ ArgoCD 已启动"

# ===============================
# 8️⃣ 自动开放防火墙
# ===============================
log "开放防火墙端口 ${NODEPORT_PORT}"

if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow ${NODEPORT_PORT}/tcp || true
    sudo ufw reload || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-port=${NODEPORT_PORT}/tcp || true
    sudo firewall-cmd --reload || true
fi

# ===============================
# 9️⃣ 获取访问 IP
# ===============================
NODE_IP=$(hostname -I | awk '{print $1}')

ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo
echo "============================================"
echo "🎉 ArgoCD 部署完成"
echo
echo "访问地址: https://${NODE_IP}:${NODEPORT_PORT}"
echo "用户名: admin"
echo "密码: ${ADMIN_PASSWORD}"
echo "============================================"
echo
