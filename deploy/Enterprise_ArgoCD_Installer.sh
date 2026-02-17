#!/bin/bash
set -euo pipefail

ARGO_NAMESPACE="argocd"
PVC_SIZE="10Gi"
STORAGE_CLASS="nfs"
HELM_RELEASE_NAME="argocd"
HELM_CHART="argo/argo-cd"

# 检查 kubectl
kubectl version --short &>/dev/null || { echo "❌ kubectl 不可用"; exit 1; }
kubectl cluster-info &>/dev/null || { echo "❌ 无法访问集群"; exit 1; }

# 创建命名空间
if ! kubectl get namespace "$ARGO_NAMESPACE" &>/dev/null; then
    kubectl create namespace "$ARGO_NAMESPACE"
    echo "✅ 命名空间 $ARGO_NAMESPACE 创建成功"
else
    echo "ℹ️ 命名空间 $ARGO_NAMESPACE 已存在"
fi

# Helm 安装检查
if ! command -v helm &>/dev/null; then
    echo "⚠️ Helm 未安装，正在安装..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# 添加仓库
if ! helm repo list | grep -q "^argo"; then
    helm repo add argo https://argoproj.github.io/argo-helm
fi
helm repo update

# 检查存储类
if ! kubectl get sc "$STORAGE_CLASS" &>/dev/null; then
    echo "❌ 存储类 $STORAGE_CLASS 不存在"; exit 1
fi

# 安装 ArgoCD
helm upgrade --install $HELM_RELEASE_NAME $HELM_CHART \
    --namespace $ARGO_NAMESPACE \
    --wait \
    --set server.service.type=LoadBalancer \
    --set server.ingress.enabled=true \
    --set server.ingress.hosts[0]=argocd.example.com \
    --set server.persistence.enabled=true \
    --set server.persistence.size=$PVC_SIZE \
    --set server.persistence.storageClass=$STORAGE_CLASS

# 获取初始密码
INITIAL_PASSWORD=$(kubectl -n $ARGO_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode)

echo "✅ ArgoCD 安装完成"
echo "URL: https://argocd.example.com"
echo "初始账号: admin"
echo "初始密码: $INITIAL_PASSWORD"
