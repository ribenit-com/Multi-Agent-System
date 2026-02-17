#!/bin/bash
# ============================================================
# 🚀 ArgoCD v2.9.1 安装脚本（DaoCloud 加速源）
# 适用于 containerd + Kubernetes
# ============================================================

set -euo pipefail

LOG_FILE="/tmp/argocd_install_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始 ArgoCD 安装"
log "📄 日志文件: $LOG_FILE"

############################
# 权限检查
############################

if [ "$EUID" -ne 0 ]; then
    log "❌ 请使用 sudo 运行该脚本"
    exit 1
fi

############################
# 需要拉取的镜像
############################

IMAGES=(
"m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
"docker.m.daocloud.io/library/redis:7.0.14-alpine"
"ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
"m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
"m.daocloud.io/docker.io/library/alpine:latest"
)

############################
# 拉取镜像
############################

log "📥 开始拉取镜像到 containerd"

for IMG in "${IMAGES[@]}"; do
    log "🔹 拉取: $IMG"
    if ctr -n k8s.io images pull "$IMG" | tee -a "$LOG_FILE"; then
        log "✅ 成功: $IMG"
    else
        log "❌ 拉取失败: $IMG"
        exit 1
    fi
done

log "✅ 所有镜像拉取完成"

############################
# Kubernetes 检查
############################

log "🔹 检查集群状态"
kubectl cluster-info | tee -a "$LOG_FILE"
kubectl get nodes -o wide | tee -a "$LOG_FILE"

############################
# 创建 namespace
############################

if ! kubectl get ns argocd &>/dev/null; then
    kubectl create ns argocd
    log "✅ 创建 namespace argocd"
else
    log "ℹ️ namespace argocd 已存在"
fi

############################
# Helm 安装
############################

if ! command -v helm &>/dev/null; then
    log "⚠️ Helm 未安装，开始安装..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

log "🚀 安装 ArgoCD"

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --wait \
  --set global.image.pullPolicy=IfNotPresent \
  --set server.image.repository=quay.io/argoproj/argocd \
  --set server.image.tag=v2.9.1 \
  --set redis.image.repository=redis \
  --set redis.image.tag=7.0.14-alpine \
  --set dex.image.repository=dexidp/dex \
  --set dex.image.tag=v2.37.0 \
  --set configmap.reload.image.repository=jimmidyson/configmap-reload \
  --set configmap.reload.image.tag=v0.8.0 \
  | tee -a "$LOG_FILE"

############################
# 获取初始密码
############################

sleep 5

PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)

log "🎉 ArgoCD 安装完成"
log "👤 admin"
log "🔑 初始密码: $PASS"
