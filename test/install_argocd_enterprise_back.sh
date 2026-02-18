#!/bin/bash
set -euo pipefail

# ==========================================
# ArgoCD 企业级自动安装脚本
# ==========================================

HTTP_PORT=${1:-30099}
HTTPS_PORT=${2:-30100}
ARGOCD_NAMESPACE="argocd"
HELM_VERSION="v3.14.4"
LOG_DIR="/mnt/truenas"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/argocd_install_${TIMESTAMP}.html"

mkdir -p "${LOG_DIR}" || true

# 初始化 HTML 日志
echo "<html><head><title>ArgoCD Install Log</title></head><body>" > "${LOG_FILE}"

log() {
    MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$MSG"
    echo "<p>$MSG</p>" >> "${LOG_FILE}"
}

error_exit() {
    log "❌ ERROR: $1"
    echo "</body></html>" >> "${LOG_FILE}"
    exit 1
}

log "🚀 开始部署 ArgoCD"

# ==========================================
# 1️⃣ 端口校验
# ==========================================
for PORT in $HTTP_PORT $HTTPS_PORT; do
    if [ "$PORT" -lt 30000 ] || [ "$PORT" -gt 32767 ]; then
        error_exit "端口必须在 30000-32767 之间"
    fi
done

# ==========================================
# 2️⃣ 检查 Kubernetes
# ==========================================
if ! kubectl cluster-info >/dev/null 2>&1; then
    error_exit "Kubernetes 未运行"
fi
log "✅ Kubernetes 正常"

# ==========================================
# 3️⃣ 检查 Helm
# ==========================================
if ! command -v helm >/dev/null 2>&1; then
    log "Helm 不存在，开始安装 ${HELM_VERSION}"

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

# ==========================================
# 4️⃣ Helm repo 检测
# ==========================================
if ! helm repo list | grep -q "^argo"; then
    log "添加 argo Helm 仓库"
    helm repo add argo https://argoproj.github.io/argo-helm
else
    log "argo repo 已存在"
fi

helm repo update >/dev/null 2>&1
log "Helm repo 更新完成"

# ==========================================
# 5️⃣ Namespace 检测
# ==========================================
if ! kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1; then
    kubectl create ns ${ARGOCD_NAMESPACE}
    log "创建 namespace ${ARGOCD_NAMESPACE}"
else
    log "namespace 已存在"
fi

# ==========================================
# 6️⃣ 生成 values.yaml
# ==========================================
cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePortHttp: ${HTTP_PORT}
    nodePortHttps: ${HTTPS_PORT}
EOF

log "已生成 NodePort 配置"

# ==========================================
# 7️⃣ 安装 / 升级 ArgoCD
# ==========================================
if helm -n ${ARGOCD_NAMESPACE} status argocd >/dev/null 2>&1; then
    log "ArgoCD 已存在，执行 upgrade"
else
    log "ArgoCD 未安装，执行 install"
fi

helm upgrade --install argocd argo/argo-cd \
  -n ${ARGOCD_NAMESPACE} \
  -f /tmp/argocd-values.yaml

log "等待 ArgoCD Server 启动..."
kubectl -n ${ARGOCD_NAMESPACE} rollout status deploy/argocd-server --timeout=300s

log "✅ ArgoCD 已启动"

# ==========================================
# 8️⃣ 防火墙开放
# ==========================================
log "检查防火墙"

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${HTTP_PORT}/tcp || true
    ufw allow ${HTTPS_PORT}/tcp || true
    ufw reload || true
    log "ufw 已放行端口"
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${HTTP_PORT}/tcp || true
    firewall-cmd --permanent --add-port=${HTTPS_PORT}/tcp || true
    firewall-cmd --reload || true
    log "firewalld 已放行端口"
fi

# ==========================================
# 9️⃣ 输出访问信息
# ==========================================
NODE_IP=$(hostname -I | awk '{print $1}')

ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

log "🎉 部署完成"
log "访问地址: https://${NODE_IP}:${HTTPS_PORT}"
log "用户名: admin"
log "密码: ${ADMIN_PASSWORD}"

echo "</body></html>" >> "${LOG_FILE}"

echo
echo "============================================"
echo "🎉 ArgoCD 部署完成"
echo "访问地址: https://${NODE_IP}:${HTTPS_PORT}"
echo "用户名: admin"
echo "密码: ${ADMIN_PASSWORD}"
echo "HTML 日志: ${LOG_FILE}"
echo "============================================"
echo
