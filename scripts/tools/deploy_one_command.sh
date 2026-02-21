#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-$GITLAB_PAT}"   # 建议从环境变量读取
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"

# ===== 临时工作目录 =====
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || exit
echo "🔹 工作目录: $WORK_DIR"

# ===== 创建 ServiceAccount + token =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建 ServiceAccount $SA_NAME 并生成 token..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN

# 打印 token
echo "🔹 ArgoCD ServiceAccount token:"
echo "$ARGOCD_AUTH_TOKEN"
echo "----------------------------"

# ===== 添加仓库到 ArgoCD =====
echo "🔹 添加仓库到 ArgoCD..."
if argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo list | grep -q "$(basename "$REPO_URL")"; then
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo update "$REPO_URL" \
        --username "$GITLAB_USER" --password "$GITLAB_PAT" --insecure
else
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo add "$REPO_URL" \
        --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" --insecure
fi

echo "🎉 仓库已成功添加到 ArgoCD，无需手动登录"
