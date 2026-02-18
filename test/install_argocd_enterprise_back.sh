#!/bin/bash

set -e

# ===============================
# 参数处理
# ===============================
HTTP_PORT=${1:-30099}
HTTPS_PORT=${2:-30100}

VERSION="Enterprise v1.0.0"
DEPLOY_TIME=$(date '+%Y-%m-%d %H:%M:%S')
SERVER_IP=$(hostname -I | awk '{print $1}')

LOG_DIR="/mnt/truenas"
SUCCESS_PAGE="${LOG_DIR}/argocd_success.html"

echo "======================================"
echo " ArgoCD Enterprise 自动安装脚本"
echo " HTTP Port : ${HTTP_PORT}"
echo " HTTPS Port: ${HTTPS_PORT}"
echo "======================================"

# ===============================
# 检测 Helm
# ===============================
if ! command -v helm >/dev/null 2>&1; then
  echo "Helm 未安装，请先安装 Helm"
  exit 1
fi

# ===============================
# 添加 Argo Helm Repo
# ===============================
if ! helm repo list | grep -q "^argo"; then
  echo "添加 argo Helm 仓库..."
  helm repo add argo https://argoproj.github.io/argo-helm
fi

helm repo update

# ===============================
# 创建 Namespace
# ===============================
if ! kubectl get ns argocd >/dev/null 2>&1; then
  kubectl create ns argocd
fi

# ===============================
# 生成 values 文件
# ===============================
cat <<EOF > /tmp/argocd-values.yaml
server:
  service:
    type: NodePort
    nodePortHttp: ${HTTP_PORT}
    nodePortHttps: ${HTTPS_PORT}
EOF

# ===============================
# 安装 / 升级 ArgoCD
# ===============================
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f /tmp/argocd-values.yaml

# ===============================
# 等待 Pod 就绪
# ===============================
echo "等待 ArgoCD Server 启动..."
kubectl rollout status deployment argocd-server -n argocd --timeout=180s

# ===============================
# 获取初始密码
# ===============================
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo "获取到初始密码"

# ===============================
# 开放防火墙（如果存在）
# ===============================
if command -v ufw >/dev/null 2>&1; then
  ufw allow ${HTTPS_PORT}/tcp || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=${HTTPS_PORT}/tcp || true
  firewall-cmd --reload || true
fi

# ===============================
# 生成企业成功页面
# ===============================
mkdir -p "${LOG_DIR}" || true

cat > "${SUCCESS_PAGE}" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>ArgoCD 部署成功</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {
    margin:0;
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial;
    background:#f5f7fa;
}
.container {
    height:100vh;
    display:flex;
    justify-content:center;
    align-items:center;
}
.card {
    background:#ffffff;
    padding:40px;
    border-radius:14px;
    box-shadow:0 12px 32px rgba(0,0,0,0.08);
    width:460px;
    text-align:center;
}
.success-icon {
    font-size:64px;
    color:#52c41a;
    margin-bottom:20px;
}
.title {
    font-size:22px;
    font-weight:600;
    margin-bottom:10px;
}
.subtitle {
    font-size:14px;
    color:#888;
    margin-bottom:25px;
}
.section {
    text-align:left;
}
.label {
    font-weight:600;
    color:#444;
    margin-top:10px;
}
.value {
    background:#f0f2f5;
    padding:10px;
    border-radius:6px;
    margin-top:5px;
    font-family:monospace;
    word-break:break-all;
}
.button {
    display:inline-block;
    margin-top:25px;
    padding:10px 22px;
    background:#1677ff;
    color:#fff;
    border-radius:6px;
    text-decoration:none;
    font-weight:500;
}
.button:hover {
    background:#4096ff;
}
.note {
    margin-top:25px;
    font-size:13px;
    color:#777;
    line-height:1.6;
}
.footer {
    margin-top:20px;
    font-size:12px;
    color:#aaa;
}
</style>
</head>

<body>
<div class="container">
  <div class="card">
    <div class="success-icon">✔</div>

    <div class="title">ArgoCD 应用引擎部署成功</div>
    <div class="subtitle">系统已成功安装并运行</div>

    <div class="section">
      <div class="label">登录地址</div>
      <div class="value">https://${SERVER_IP}:${HTTPS_PORT}</div>

      <div class="label">用户名</div>
      <div class="value">admin</div>

      <div class="label">初始密码</div>
      <div class="value">${ARGOCD_PASSWORD}</div>
    </div>

    <a class="button" href="https://${SERVER_IP}:${HTTPS_PORT}" target="_blank">
      立即访问控制台
    </a>

    <div class="note">
      ⚠ 首次登录后请立即修改密码<br>
      ⚠ 若无法访问，请检查防火墙端口是否开放<br>
      ⚠ 浏览器提示 HTTPS 安全警告属于正常现象
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

echo "======================================"
echo " 部署完成！"
echo " 访问地址: https://${SERVER_IP}:${HTTPS_PORT}"
echo " 用户名: admin"
echo " 密码: ${ARGOCD_PASSWORD}"
echo " 成功页面: ${SUCCESS_PAGE}"
echo "======================================"
