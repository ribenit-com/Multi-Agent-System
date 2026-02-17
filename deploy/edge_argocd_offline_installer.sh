#!/bin/bash
set -e

# -------------------------------
# 变量定义
# -------------------------------
NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

ARGOCD_NAMESPACE="argocd"
NODEPORT_PORT=30100
HELM_BIN="/usr/local/bin/helm"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# 镜像列表（离线拉取）
IMAGES=(
"m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
"docker.m.daocloud.io/library/redis:7.0.14-alpine"
"ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
"m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
"m.daocloud.io/docker.io/library/alpine:latest"
)

# -------------------------------
# 日志函数
# -------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# -------------------------------
# Helm 安装
# -------------------------------
if ! command -v helm &> /dev/null; then
    log "🔹 Helm 未安装，正在安装..."
    curl -sSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz -o /tmp/helm.tar.gz
    tar -xzf /tmp/helm.tar.gz -C /tmp
    sudo mv /tmp/linux-amd64/helm $HELM_BIN
    sudo chmod +x $HELM_BIN
    log "✅ Helm 安装完成"
else
    log "✅ Helm 已安装: $(helm version --short)"
fi

# -------------------------------
# 创建命名空间
# -------------------------------
if ! kubectl get ns "$ARGOCD_NAMESPACE" &>/dev/null; then
    log "🔹 创建命名空间 $ARGOCD_NAMESPACE ..."
    kubectl create ns "$ARGOCD_NAMESPACE"
else
    log "ℹ️ 命名空间 $ARGOCD_NAMESPACE 已存在"
fi

# -------------------------------
# StorageClass 检查与部署
# -------------------------------
if ! kubectl get sc local-path &>/dev/null; then
    log "🔹 StorageClass local-path 不存在，部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    # 等待 Pod 就绪
    log "🔹 等待 local-path-provisioner Pod 就绪..."
    kubectl -n local-path-storage wait --for=condition=Ready pod -l app=local-path-provisioner --timeout=120s
else
    log "✅ StorageClass local-path 已存在"
fi

# -------------------------------
# 拉取镜像
# -------------------------------
log "🔹 拉取镜像..."
for IMG in "${IMAGES[@]}"; do
    log "📥 拉取: $IMG"
    if sudo ctr -n k8s.io images pull "$IMG"; then
        log "✅ 成功: $IMG"
    else
        log "❌ 拉取失败: $IMG，请检查网络或权限"
    fi
done
log "✅ 所有镜像拉取完成"

# -------------------------------
# ArgoCD Helm 安装/升级
# -------------------------------
log "🔹 添加 ArgoCD Helm 仓库..."
$HELM_BIN repo add argo https://argoproj.github.io/argo-helm || true
$HELM_BIN repo update

log "🔹 安装 ArgoCD Helm Chart..."
cat <<EOF > /tmp/argocd_values.yaml
server:
  service:
    type: NodePort
    nodePort: $NODEPORT_PORT
    port: 443
    targetPort: 8080
EOF

$HELM_BIN upgrade --install argocd argo/argo-cd \
    -n "$ARGOCD_NAMESPACE" \
    -f /tmp/argocd_values.yaml

# -------------------------------
# 等待 ArgoCD Server Pod 就绪
# -------------------------------
log "🔹 等待 argocd-server Pod 就绪..."
kubectl -n "$ARGOCD_NAMESPACE" wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server --timeout=180s

# -------------------------------
# 开放防火墙端口
# -------------------------------
log "🔹 开放 NodePort 端口 $NODEPORT_PORT"
sudo ufw allow "$NODEPORT_PORT"/tcp || true

# -------------------------------
# 生成 HTML 页面
# -------------------------------
ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ADMIN_USER="admin"
HTML_FILE="$NAS_DIR/argocd_login.html"

cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>ArgoCD 登录信息</title>
</head>
<body>
<h1>ArgoCD 登录信息</h1>
<p>访问地址: <a href="https://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):$NODEPORT_PORT/" target="_blank">ArgoCD Web</a></p>
<p>账号: <b>$ADMIN_USER</b></p>
<p>初始密码: <b>$ADMIN_PASSWORD</b></p>
</body>
</html>
EOF

log "🎉 安装完成，登录信息已生成: $HTML_FILE"
