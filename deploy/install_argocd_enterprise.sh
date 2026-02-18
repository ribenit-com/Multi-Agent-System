#!/bin/bash
set -Eeuo pipefail

# ==========================================
# ArgoCD 企业级自动安装脚本 (增强版)
# ==========================================

HTTP_PORT=${1:-30099}
HTTPS_PORT=${2:-30100}
ARGOCD_NAMESPACE="argocd"
HELM_VERSION="v3.14.4"
LOG_DIR="/mnt/truenas"
VERSION="Enterprise v2.0.0"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/argocd_install_${TIMESTAMP}.html"

mkdir -p "${LOG_DIR}" || true

# ===============================
# HTML 初始化
# ===============================
echo "<html><head><meta charset='UTF-8'><title>ArgoCD Install</title></head><body>" > "${LOG_FILE}"

log() {
    MSG="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$MSG"
    echo "<p>$MSG</p>" >> "${LOG_FILE}"
}

fail() {
    log "❌ $1"
    echo "</body></html>" >> "${LOG_FILE}"
    exit 1
}

log "🚀 开始部署 ArgoCD"

# ===============================
# 端口校验
# ===============================
for PORT in $HTTP_PORT $HTTPS_PORT; do
    [[ "$PORT" -ge 30000 && "$PORT" -le 32767 ]] || fail "端口必须在 30000-32767 之间"
done

# ===============================
# 检查 kubectl
# ===============================
command -v kubectl >/dev/null 2>&1 || fail "kubectl 未安装"

# ===============================
# 检查 Kubernetes
# ===============================
kubectl cluster-info >/dev/null 2>&1 || fail "Kubernetes 未运行"
log "✅ Kubernetes 正常"

# ===============================
# 检查 Helm
# ===============================
if ! command -v helm >/dev/null 2>&1; then
    log "Helm 未安装，开始自动安装 ${HELM_VERSION}"

    TMP_DIR=$(mktemp -d)
    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o ${TMP_DIR}/helm.tar.gz
    tar -xzf ${TMP_DIR}/helm.tar.gz -C ${TMP_DIR}
    install -m 0755 ${TMP_DIR}/linux-amd64/helm /usr/local/bin/helm
    rm -rf ${TMP_DIR}

    log "✅ Helm 安装完成"
else
    log "✅ Helm 已存在"
fi

# ===============================
# Helm repo
# ===============================
if ! helm repo list | grep -q "^argo"; then
    log "添加 argo Helm 仓库"
    helm repo add argo https://argoproj.github.io/argo-helm
fi

helm repo update >/dev/null
log "Helm repo 更新完成"

# ===============================
# Namespace
# ===============================
kubectl get ns ${ARGOCD_NAMESPACE} >/dev/null 2>&1 || {
    kubectl create ns ${ARGOCD_NAMESPACE}
    log "创建 namespace ${ARGOCD_NAMESPACE}"
}

# ===============================
# values.yaml
# ===============================
cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePortHttp: ${HTTP_PORT}
    nodePortHttps: ${HTTPS_PORT}
EOF

log "已生成 NodePort 配置"

# ===============================
# 安装 / 升级
# ===============================
if helm -n ${ARGOCD_NAMESPACE} status argocd >/dev/null 2>&1; then
    log "执行 upgrade"
else
    log "执行 install"
fi

helm upgrade --install argocd argo/argo-cd \
  -n ${ARGOCD_NAMESPACE} \
  -f /tmp/argocd-values.yaml

log "等待 ArgoCD 启动..."
kubectl -n ${ARGOCD_NAMESPACE} rollout status deploy/argocd-server --timeout=300s

log "✅ ArgoCD 已启动"

# ===============================
# 防火墙
# ===============================
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
# 获取访问信息
# ===============================
NODE_IP=$(hostname -I | awk '{print $1}')
ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

DEPLOY_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ===============================
# 生成企业成功页面
# ===============================
SUCCESS_PAGE="${LOG_DIR}/argocd_success.html"

cat > "${SUCCESS_PAGE}" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>ArgoCD 部署成功</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto;background:#f5f7fa}
.container{height:100vh;display:flex;justify-content:center;align-items:center}
.card{background:#fff;padding:40px;border-radius:14px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:460px;text-align:center}
.icon{font-size:64px;color:#52c41a;margin-bottom:20px}
.title{font-size:22px;font-weight:600;margin-bottom:10px}
.subtitle{font-size:14px;color:#888;margin-bottom:25px}
.label{font-weight:600;color:#444;margin-top:12px;text-align:left}
.value{background:#f0f2f5;padding:10px;border-radius:6px;margin-top:5px;font-family:monospace;text-align:left}
.button{display:inline-block;margin-top:25px;padding:10px 22px;background:#1677ff;color:#fff;border-radius:6px;text-decoration:none}
.footer{margin-top:20px;font-size:12px;color:#aaa}
.note{margin-top:20px;font-size:13px;color:#777;line-height:1.6}
</style>
</head>
<body>
<div class="container">
<div class="card">
<div class="icon">✔</div>
<div class="title">ArgoCD 部署成功</div>
<div class="subtitle">系统已成功安装并运行</div>

<div class="label">登录地址</div>
<div class="value">https://${NODE_IP}:${HTTPS_PORT}</div>

<div class="label">用户名</div>
<div class="value">admin</div>

<div class="label">初始密码</div>
<div class="value">${ADMIN_PASSWORD}</div>

<a class="button" href="https://${NODE_IP}:${HTTPS_PORT}" target="_blank">立即访问</a>

<div class="note">
⚠ 首次登录后请修改密码<br>
⚠ HTTPS 证书警告属于正常现象
</div>

<div class="footer">
版本：${VERSION}<br>
部署时间：${DEPLOY_TIME}
</div>
</div>
</div>
</body>
</html>
EOF

echo "</body></html>" >> "${LOG_FILE}"

echo
echo "======================================"
echo "🎉 ArgoCD 部署完成"
echo "访问地址: https://${NODE_IP}:${HTTPS_PORT}"
echo "用户名: admin"
echo "密码: ${ADMIN_PASSWORD}"
echo "成功页面: ${SUCCESS_PAGE}"
echo "======================================"
