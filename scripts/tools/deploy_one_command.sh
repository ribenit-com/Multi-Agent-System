#!/bin/bash
# ===================================================
# 一键部署 GitLab/GitHub 仓库到 ArgoCD v2.1
# 功能：
#   - 创建 ServiceAccount + ArgoCD token
#   - 打印 token
#   - 自动配置仓库到 ArgoCD（使用 token 登录）
# ===================================================
set -euo pipefail

# 配置区
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-<YOUR_NEW_GITHUB_TOKEN>}"
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-ns-gitlab-ha}"
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"

# 临时工作目录
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || exit
echo "🔹 工作目录: $WORK_DIR"

# 创建 ServiceAccount + token
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建 ServiceAccount $SA_NAME 并生成 token..."
kubectl -n "$ARGO_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGO_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGO_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGO_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN
echo "✅ 自动生成 token 并导出环境变量"

# 打印 token
echo "🔹 ArgoCD ServiceAccount token:"
echo "$ARGOCD_AUTH_TOKEN"
echo "----------------------------"

# 配置仓库到 ArgoCD（使用 token 登录）
echo "🔹 配置 ArgoCD 仓库凭证..."
if argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo list | grep -q "$(basename "$REPO_URL")"; then
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo update "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --insecure
else
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" --insecure
fi

echo "🎉 仓库已成功配置到 ArgoCD，使用 token 登录完成部署准备"
