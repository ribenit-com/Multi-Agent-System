#!/bin/bash
# ==================================================================
# 🤖 企业级 ArgoCD 安装器（多镜像源 + 本地化 + StorageClass自动创建）
# 自动检查集群、kubectl、Helm、存储，输出详细日志
# 日志存储在 /mnt/truenas/logs
# ==================================================================

set -euo pipefail

# ---------------- 配置 ----------------
LOG_DIR="/mnt/truenas/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/Enterprise_ArgoCD_Installer_$(date +%Y%m%d_%H%M%S).log"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

ARGO_NAMESPACE="argocd"
PVC_SIZE="10Gi"
STORAGE_CLASS="local-path"
HELM_RELEASE_NAME="argocd"
HELM_CHART="argo/argo-cd"
HELM_REPO="https://argoproj.github.io/argo-helm"

# 多镜像源列表（按优先级）
IMAGES=(
    "docker.io/argoproj/argocd:v2.9.1"
    "ghcr.io/argoproj/argocd:v2.9.1"
    "registry.cn-hangzhou.aliyuncs.com/argoproj/argocd:v2.9.1"
)

log "🔹 安装日志输出到 $LOG_FILE"
log "🔹 当前节点 IP: $(hostname -I | awk '{print $1}')"
log "🔹 当前 KUBECONFIG: ${KUBECONFIG:-~/.kube/config}"

# ---------------- 检查 kubectl ----------------
log "🔹 检查 kubectl 可用性..."
if ! command -v kubectl >/dev/null 2>&1; then
    log "❌ kubectl 未安装，请先安装 kubectl"
    exit 1
fi
log "🔹 kubectl 版本信息："
kubectl version --client=true | tee -a "$LOG_FILE"

log "🔹 测试访问集群..."
if ! kubectl cluster-info &>/dev/null; then
    log "❌ 无法访问 Kubernetes 集群，请检查 KUBECONFIG 和网络"
    exit 1
fi
kubectl get nodes -o wide | tee -a "$LOG_FILE"

# ---------------- 创建命名空间 ----------------
log "🔹 检查/创建命名空间 $ARGO_NAMESPACE..."
if ! kubectl get namespace "$ARGO_NAMESPACE" &>/dev/null; then
    kubectl create namespace "$ARGO_NAMESPACE"
    log "✅ 命名空间 $ARGO_NAMESPACE 创建成功"
else
    log "ℹ️ 命名空间 $ARGO_NAMESPACE 已存在"
fi

# ---------------- Helm 安装 ----------------
if ! command -v helm >/dev/null 2>&1; then
    log "⚠️ Helm 未安装，正在安装..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash | tee -a "$LOG_FILE"
fi
log "🔹 Helm 版本信息："
helm version | tee -a "$LOG_FILE"

# 添加 Argo Helm 仓库
if ! helm repo list | grep -q "^argo"; then
    log "🔹 添加 Argo Helm 仓库..."
    helm repo add argo "$HELM_REPO"
fi
helm repo update | tee -a "$LOG_FILE"

# ---------------- StorageClass ----------------
log "🔹 检查 StorageClass $STORAGE_CLASS..."
if ! kubectl get sc "$STORAGE_CLASS" &>/dev/null; then
    log "⚠️ StorageClass $STORAGE_CLASS 不存在，自动部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml | tee -a "$LOG_FILE"
    log "🔹 等待 local-path-provisioner Pod 就绪..."
    kubectl -n local-path-storage wait --for=condition=ready pod -l app=local-path-provisioner --timeout=180s
    log "✅ StorageClass $STORAGE_CLASS 已创建并可用"
else
    log "✅ StorageClass $STORAGE_CLASS 已存在"
fi

# ---------------- 镜像检查 ----------------
log "🔹 检查本地是否已有 ArgoCD 镜像..."
FOUND_IMAGE=""
for IMAGE in "${IMAGES[@]}"; do
    if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE}$"; then
        log "✅ 本地已有镜像 $IMAGE"
        FOUND_IMAGE=$IMAGE
        break
    else
        log "⚠️ 本地无镜像 $IMAGE，尝试拉取..."
        if docker pull "$IMAGE"; then
            log "✅ 镜像拉取成功: $IMAGE"
            FOUND_IMAGE=$IMAGE
            break
        else
            log "❌ 镜像拉取失败: $IMAGE，尝试下一个镜像源"
        fi
    fi
done

if [ -z "$FOUND_IMAGE" ]; then
    log "❌ 所有镜像源拉取失败，请检查网络和镜像仓库"
    exit 1
fi

REPO=$(echo "$FOUND_IMAGE" | cut -d':' -f1)
TAG=$(echo "$FOUND_IMAGE" | cut -d':' -f2)

# ---------------- 安装 ArgoCD ----------------
log "🔹 安装 ArgoCD Helm Chart..."
helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART" \
    --namespace "$ARGO_NAMESPACE" \
    --wait \
    --set server.service.type=LoadBalancer \
    --set server.ingress.enabled=true \
    --set server.ingress.hosts[0]=argocd.example.com \
    --set server.persistence.enabled=true \
    --set server.persistence.size="$PVC_SIZE" \
    --set server.persistence.storageClass="$STORAGE_CLASS" \
    --set server.image.repository="$REPO" \
    --set server.image.tag="$TAG" | tee -a "$LOG_FILE"

# ---------------- 获取初始密码 ----------------
log "🔹 获取 ArgoCD 初始密码..."
if kubectl -n "$ARGO_NAMESPACE" get secret argocd-initial-admin-secret &>/dev/null; then
    INITIAL_PASSWORD=$(kubectl -n "$ARGO_NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" | base64 --decode)
    log "✅ ArgoCD 安装完成"
    log "URL: https://argocd.example.com"
    log "初始账号: admin"
    log "初始密码: $INITIAL_PASSWORD"
else
    log "❌ 未找到 argocd-initial-admin-secret，请检查 Helm 安装状态"
fi

log "🔹 安装完成，详细日志请查看 $LOG_FILE"
