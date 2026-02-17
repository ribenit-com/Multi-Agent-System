#!/bin/bash
set -euo pipefail

# ---------------------------
# 配置
# ---------------------------
NAS_DIR="/mnt/truenas"
LOG_FILE="$NAS_DIR/Enterprise_ArgoCD_Installer_$(date +%Y%m%d_%H%M%S).log"
STORAGE_CLASS="local-path"
ARCDOC_NAMESPACE="argocd"
ARCDOC_RELEASE="argocd"
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)

# ---------------------------
# 日志函数
# ---------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ---------------------------
# 检查 Kubectl
# ---------------------------
log "🔹 当前节点 IP: $(hostname -I | awk '{print $1}')"
log "🔹 当前 KUBECONFIG: ${KUBECONFIG:-/home/$USER/.kube/config}"
log "🔹 检查 kubectl 可用性..."
kubectl version --client=true

# ---------------------------
# 检查/创建命名空间
# ---------------------------
log "🔹 检查/创建命名空间 $ARCDOC_NAMESPACE..."
if kubectl get ns "$ARCDOC_NAMESPACE" >/dev/null 2>&1; then
    log "ℹ️ 命名空间 $ARCDOC_NAMESPACE 已存在"
else
    kubectl create ns "$ARCDOC_NAMESPACE"
    log "✅ 命名空间 $ARCDOC_NAMESPACE 创建成功"
fi

# ---------------------------
# 检查/创建 StorageClass
# ---------------------------
log "🔹 检查 StorageClass $STORAGE_CLASS..."
if kubectl get sc "$STORAGE_CLASS" >/dev/null 2>&1; then
    log "✅ StorageClass $STORAGE_CLASS 已存在"
else
    log "⚠️ StorageClass $STORAGE_CLASS 不存在，正在自动部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    log "✅ StorageClass $STORAGE_CLASS 已创建"
fi

# ---------------------------
# 拉取镜像
# ---------------------------
log "🔹 检查本地镜像并拉取缺失镜像..."
for IMG in "${IMAGES[@]}"; do
    log "🔹 镜像: $IMG"
    if sudo ctr -n k8s.io images list | grep -q "$(basename "$IMG")"; then
        log "✅ 本地已有镜像 $IMG"
    else
        log "⚠️ 本地无镜像 $IMG，尝试拉取..."
        if sudo ctr -n k8s.io images pull "$IMG"; then
            log "✅ 成功: $IMG"
        else
            log "❌ 拉取失败: $IMG"
        fi
    fi
done

# ---------------------------
# 安装/升级 ArgoCD Helm Chart
# ---------------------------
log "🔹 添加 ArgoCD Helm 仓库..."
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

log "🔹 安装/升级 ArgoCD Helm Chart..."
if helm status "$ARCDOC_RELEASE" -n "$ARCDOC_NAMESPACE" >/dev/null 2>&1; then
    helm upgrade "$ARCDOC_RELEASE" argo/argo-cd -n "$ARCDOC_NAMESPACE"
else
    helm install "$ARCDOC_RELEASE" argo/argo-cd -n "$ARCDOC_NAMESPACE"
fi

# ---------------------------
# 获取 admin 密码
# ---------------------------
PASS=$(kubectl -n "$ARCDOC_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
log "🔑 初始密码: $PASS"

# ---------------------------
# 生成 HTML 登录页
# ---------------------------
HTML_FILE="$NAS_DIR/argocd_login.html"
SERVER_IP=$(hostname -I | awk '{print $1}')

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ArgoCD Login</title>
<style>
body { font-family: Arial; background:#0f172a; color:#fff; text-align:center; padding-top:80px; }
.container { background:#1e293b; width:500px; margin:auto; padding:40px; border-radius:12px; box-shadow:0 0 20px rgba(0,0,0,0.5);}
h1 { color:#38bdf8; }
.info { margin-top:20px; font-size:18px; }
.password { background:#334155; padding:10px; border-radius:6px; font-weight:bold; color:#22c55e; }
a { color:#facc15; }
</style>
</head>
<body>
<div class="container">
<h1>🚀 ArgoCD 部署成功</h1>
<div class="info">
<p><b>访问地址：</b></p>
<p><a href="https://${SERVER_IP}:8080" target="_blank">https://${SERVER_IP}:8080</a></p>
<p><b>账号：</b> admin</p>
<p><b>密码：</b></p>
<div class="password">${PASS}</div>
<p style="margin-top:30px;font-size:14px;color:#94a3b8;">部署时间：$(date)</p>
</div>
</div>
</body>
</html>
EOF
chmod 644 "$HTML_FILE"
log "🌐 登录页面已生成: $HTML_FILE"

log "🎉 安装完成！所有日志和页面已保存到 $NAS_DIR"
