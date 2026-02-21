#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"

# ===== 检查必要参数 =====
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 错误: 请设置 GITLAB_PAT 环境变量"
    echo "   例如: export GITLAB_PAT='ghp_xxxx'"
    exit 1
fi

# ===== 创建 ServiceAccount (保留 Kubernetes 权限, 可选) =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 自动获取 ArgoCD admin 密码 =====
echo "🔹 获取 ArgoCD admin 密码 ..."
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# ===== 登录 ArgoCD 并生成 token =====
echo "🔹 登录 ArgoCD 并生成 API token ..."
argocd login "$ARGOCD_SERVER" \
    --username admin \
    --password "$ARGOCD_PASSWORD" \
    --insecure \
    --grpc-web

ARGOCD_TOKEN=$(argocd account generate-token --account admin)

echo "🔹 Token 前20字符: ${ARGOCD_TOKEN:0:20} ..."

# ===== 添加仓库到 ArgoCD =====
echo "🔹 添加仓库 $REPO_URL 到 ArgoCD ..."
argocd repo add "$REPO_URL" \
    --username "$GITLAB_USER" \
    --password "$GITLAB_PAT" \
    --name "$ARGO_APP" \
    --insecure \
    --grpc-web \
    --server "$ARGOCD_SERVER" \
    --auth-token "$ARGOCD_TOKEN"

echo "✅ 仓库添加完成"

# ===== 显示当前 ArgoCD 仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd repo list --server "$ARGOCD_SERVER" --grpc-web --auth-token "$ARGOCD_TOKEN" | awk '{print $1 " -> " $2}'

echo "🎉 一键添加仓库完成"
