#!/bin/bash
# ===================================================
# 一键部署 GitLab/GitHub 仓库到 ArgoCD v3.0
# 功能：
#   - 创建 ServiceAccount + ArgoCD token
#   - 打印 token
#   - 自动配置仓库到 ArgoCD（使用 token 登录）
# ===================================================
set -euo pipefail

# ===== 配置区 =====
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-<YOUR_GITHUB_TOKEN>}"  # GitHub 或 GitLab Token
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-ns-gitlab-ha}"
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"

# ===== 临时工作目录 =====
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || exit
echo "🔹 工作目录: $WORK_DIR"

# ===== 创建 ServiceAccount + token =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建 ServiceAccount $SA_NAME 并生成 token..."
kubectl -n "$ARGO_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGO_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGO_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGO_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN
echo "✅ 自动生成 token并导出环境变量"

# 打印 token
echo "🔹 ArgoCD ServiceAccount token:"
echo "$ARGOCD_AUTH_TOKEN"
echo "----------------------------"

# ===== 配置 ArgoCD 仓库 =====
echo "🔹 配置 ArgoCD 仓库凭证..."
if argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo list | grep -q "$(basename "$REPO_URL")"; then
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo update "$REPO_URL" \
        --username "$GITLAB_USER" --password "$GITLAB_PAT" --insecure
else
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" repo add "$REPO_URL" \
        --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" --insecure
fi

# ===== 下载并执行 deploy_gitlab_to_argocd_.sh =====
RUN_SCRIPT="deploy_gitlab_to_argocd_.sh"
RUN_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"
echo "🔹 下载最新部署脚本..."
curl -sSL "$RUN_URL" -o "$RUN_SCRIPT"
chmod +x "$RUN_SCRIPT"
echo "✅ 最新部署脚本已下载: $RUN_SCRIPT"

# 执行部署脚本（传递 token）
echo "🔹 执行部署脚本..."
ARGO_APP="$ARGO_APP" \
ARGO_NAMESPACE="$ARGO_NAMESPACE" \
DEPLOY_NAMESPACE="$DEPLOY_NAMESPACE" \
REPO_URL="$REPO_URL" \
ARGOCD_SERVER="$ARGOCD_SERVER" \
ARGOCD_AUTH_TOKEN="$ARGOCD_AUTH_TOKEN" \
./"$RUN_SCRIPT"

echo "🎉 GitLab/GitHub -> ArgoCD 自动部署完成"
