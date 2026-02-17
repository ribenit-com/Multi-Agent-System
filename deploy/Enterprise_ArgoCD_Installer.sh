#!/bin/bash
# ==================================================================
# 🤖 企业级 ArgoCD 安装脚本 - 本地 PVC + 可选备份同步
# 安装在 Kubernetes Pod 内，生产环境推荐 Helm
# ==================================================================

set -euo pipefail

# ---------------- 配置 ----------------
ARGO_NAMESPACE="argocd"
PVC_SIZE="10Gi"
STORAGE_CLASS="local-storage"   # 本地存储类，企业推荐用节点本地卷
HELM_RELEASE_NAME="argocd"
HELM_CHART="argo/argo-cd"
HELM_REPO="https://argoproj.github.io/argo-helm"
NAS_BACKUP_DIR="/mnt/truenas/argocd-backup"  # 可选同步目录

# ---------------- 前置检查 ----------------
echo "🔹 检查 kubectl..."
kubectl version --short &>/dev/null || { echo "❌ kubectl 不可用"; exit 1; }
kubectl cluster-info &>/dev/null || { echo "❌ 无法访问集群"; exit 1; }

echo "🔹 检查 Helm..."
if ! command -v helm &>/dev/null; then
    echo "⚠️ Helm 未安装，正在安装..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "🔹 创建命名空间 $ARGO_NAMESPACE..."
if ! kubectl get namespace "$ARGO_NAMESPACE" &>/dev/null; then
    kubectl create namespace "$ARGO_NAMESPACE"
    echo "✅ 命名空间 $ARGO_NAMESPACE 创建成功"
else
    echo "ℹ️ 命名空间 $ARGO_NAMESPACE 已存在"
fi

echo "🔹 添加 Argo Helm 仓库..."
helm repo add argo $HELM_REPO || true
helm repo update

echo "🔹 检查存储类 $STORAGE_CLASS..."
if ! kubectl get sc "$STORAGE_CLASS" &>/dev/null; then
    echo "❌ 存储类 $STORAGE_CLASS 不存在"; exit 1
fi

# ---------------- 安装 ArgoCD ----------------
echo "🔹 安装 ArgoCD..."
helm upgrade --install $HELM_RELEASE_NAME $HELM_CHART \
    --namespace $ARGO_NAMESPACE \
    --wait \
    --timeout 5m \
    --set server.service.type=LoadBalancer \
    --set server.ingress.enabled=true \
    --set server.ingress.hosts[0]=argocd.example.com \
    --set server.persistence.enabled=true \
    --set server.persistence.size=$PVC_SIZE \
    --set server.persistence.storageClass=$STORAGE_CLASS \
    --set server.persistence.persistentVolumeReclaimPolicy=Retain

# ---------------- 等待 Pod 就绪 ----------------
echo "🔹 等待 ArgoCD Server Pod 启动..."
kubectl -n $ARGO_NAMESPACE wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --timeout=180s

# ---------------- 获取初始密码 ----------------
INITIAL_PASSWORD=$(kubectl -n $ARGO_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

# ---------------- 可选 NAS 备份 ----------------
if [ -d "$NAS_BACKUP_DIR" ]; then
    echo "🔹 同步 PVC 数据到 NAS..."
    # 简单示例：rsync 同步本地 PVC 挂载目录到 NAS
    # 注意：这里假设本地 PVC 挂载路径已知，例如 /mnt/local-argocd
    LOCAL_PVC_PATH="/mnt/local-argocd"
    rsync -avh --delete "$LOCAL_PVC_PATH/" "$NAS_BACKUP_DIR/"
    echo "✅ 数据同步完成"
fi

# ---------------- 完成提示 ----------------
echo "✅ ArgoCD 企业级安装完成"
echo "URL: https://argocd.example.com"
echo "初始账号: admin"
echo "初始密码: $INITIAL_PASSWORD"

echo "💡 提示："
echo "- 本地 PVC 使用 Retain 策略，Pod 删除数据不丢失"
echo "- 如需备份到 NAS，请确保 NAS 挂载并在 NAS_BACKUP_DIR 设置正确路径"
