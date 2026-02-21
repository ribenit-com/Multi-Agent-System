#!/bin/bash
set -euo pipefail

ARGOCD_SERVER="192.168.1.10:30100"
ARGOCD_NAMESPACE="argocd"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-$GITLAB_PAT}"  # 从环境变量读取
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"

# 创建 ServiceAccount 并生成 token
SA_NAME="gitlab-deployer-sa"
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN

echo "🔹 ArgoCD ServiceAccount token:"
echo "$ARGOCD_AUTH_TOKEN"
echo "----------------------------"

# 用 token 自动添加仓库
argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo add "$REPO_URL" \
    --username "$GITLAB_USER" \
    --password "$GITLAB_PAT" \
    --name "gitlab" \
    --insecure

echo "🎉 仓库已成功添加到 ArgoCD，无需手动登录"
