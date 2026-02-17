#!/bin/bash
# ============================================================
# 🚀 Enterprise Edge ArgoCD Offline Installer
# For Kubernetes + containerd
# NAS 仅存日志与离线镜像
# ============================================================

set -e

#########################
# 基础变量
#########################

ARGO_VERSION="v2.9.1"
ARGO_NAMESPACE="argocd"
STORAGE_CLASS="local-path"
NAS_DIR="/mnt/truenas/logs"
LOG_FILE="$NAS_DIR/ArgoCD_Install_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$NAS_DIR"

log() {
    echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

log "🚀 开始企业级 ArgoCD 离线安装"
log "📄 日志文件: $LOG_FILE"

#########################
# 权限检测
#########################

if [ "$EUID" -ne 0 ]; then
    log "❌ 请使用 sudo 运行脚本"
    exit 1
fi

#########################
# 检查集群
#########################

log "🔹 检查 Kubernetes 集群状态"
kubectl cluster-info | tee -a "$LOG_FILE"
kubectl get nodes -o wide | tee -a "$LOG_FILE"

#########################
# 创建 Namespace
#########################

if ! kubectl get ns $ARGO_NAMESPACE &>/dev/null; then
    kubectl create ns $ARGO_NAMESPACE
    log "✅ Namespace 创建成功"
else
    log "ℹ️ Namespace 已存在"
fi

#########################
# StorageClass 检查
#########################

if ! kubectl get sc $STORAGE_CLASS &>/dev/null; then
    log "⚠️ StorageClass 不存在，正在部署 local-path"
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    kubectl -n local-path-storage wait --for=condition=ready pod -l app=local-path-provisioner --timeout=180s
    log "✅ local-path 已创建"
else
    log "✅ StorageClass 已存在"
fi

#########################
# 预拉镜像（加速源）
#########################

IMAGES=(
"m.daocloud.io/docker.io/argoproj/argocd:${ARGO_VERSION}|argocd_${ARGO_VERSION}.tar"
"m.daocloud.io/docker.io/redis:7-alpine|redis_7-alpine.tar"
"m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0|configmap-reload_v0.8.0.tar"
)

log "📥 开始预拉 ArgoCD 所需镜像"

for item in "${IMAGES[@]}"; do
    IMG_SRC="${item%%|*}"
    IMG_FILE="${item##*|}"

    log "🔹 拉取镜像: $IMG_SRC"

    if ctr -n k8s.io images pull "$IMG_SRC"; then
        log "📦 导出到 NAS: $NAS_DIR/$IMG_FILE"
        ctr -n k8s.io images export "$NAS_DIR/$IMG_FILE" "$IMG_SRC"
        chmod 644 "$NAS_DIR/$IMG_FILE"
        log "✅ 完成: $IMG_SRC"
    else
        log "❌ 拉取失败: $IMG_SRC"
        exit 1
    fi
done

#########################
# Helm 安装
#########################

log "🔹 检查 Helm"

if ! command -v helm &>/dev/null; then
    log "⚠️ Helm 未安装，正在安装"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

log "🚀 安装 ArgoCD"

helm upgrade --install argocd argo/argo-cd \
  --namespace $ARGO_NAMESPACE \
  --set global.image.repository=argoproj/argocd \
  --set global.image.tag=${ARGO_VERSION} \
  --set global.image.pullPolicy=IfNotPresent \
  --set redis.image.repository=redis \
  --set redis.image.tag=7-alpine \
  --wait | tee -a "$LOG_FILE"

#########################
# 获取初始密码
#########################

sleep 5

if kubectl -n $ARGO_NAMESPACE get secret argocd-initial-admin-secret &>/dev/null; then
    PASS=$(kubectl -n $ARGO_NAMESPACE get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" | base64 --decode)

    log "🎉 ArgoCD 安装成功"
    log "👤 用户名: admin"
    log "🔑 初始密码: $PASS"
else
    log "⚠️ 未获取到初始密码，请检查 Pod 状态"
fi

log "🏁 安装流程结束"
