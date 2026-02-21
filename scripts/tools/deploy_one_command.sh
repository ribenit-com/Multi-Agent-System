#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 一条命令式部署脚本 v1.5.0
# 功能：
#   - 下载最新部署脚本
#   - 配置 GitLab PAT
#   - 自动创建 ArgoCD ServiceAccount token
#   - 自动使用 token 登录 ArgoCD
#   - 创建/更新 ArgoCD Application
#   - 等待同步完成
# ===================================================
set -euo pipefail

# ====== 配置区 ======
GITLAB_USER="${GITLAB_USER:-zuandilong@gmail.com}"
GITLAB_PAT="${GITLAB_PAT:-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}"
REPO_URL="${REPO_URL:-https://gitlab.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
REPO_PATH="${REPO_PATH:-gitlab-gitops}"
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-ns-gitlab-ha}"
TIMEOUT="${TIMEOUT:-900}"  # 等待 15 分钟

# ====== ArgoCD 服务器信息 ======
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"

# ====== 临时工作目录 ======
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || exit
echo "🔹 工作目录: $WORK_DIR"

# ====== 1️⃣ 下载最新部署脚本 ======
RUN_SCRIPT="deploy_gitlab_to_argocd_.sh"
RUN_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"
echo "🔹 下载最新部署脚本..."
curl -sSL "$RUN_URL" -o "$RUN_SCRIPT"
chmod +x "$RUN_SCRIPT"
echo "✅ 最新部署脚本已下载: $RUN_SCRIPT"

# ====== 2️⃣ 创建 ServiceAccount + token（自动化使用） ======
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建 ServiceAccount $SA_NAME 并生成 token..."
kubectl -n "$ARGO_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGO_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGO_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# 生成 token
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGO_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN
echo "✅ 自动生成 token 并导出环境变量"

# ====== 3️⃣ 配置 ArgoCD 仓库凭证 ======
echo "🔹 配置 ArgoCD 仓库凭证..."
if argocd --server "$ARGOCD_SERVER" repo list | grep -q "$(basename "$REPO_URL")"; then
    argocd --server "$ARGOCD_SERVER" repo update "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT"
else
    argocd --server "$ARGOCD_SERVER" repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP"
fi

# ====== 4️⃣ 执行部署脚本 ======
echo "🔹 执行部署脚本..."
ARGO_APP="$ARGO_APP" \
ARGO_NAMESPACE="$ARGO_NAMESPACE" \
DEPLOY_NAMESPACE="$DEPLOY_NAMESPACE" \
REPO_URL="$REPO_URL" \
REPO_PATH="$REPO_PATH" \
TIMEOUT="$TIMEOUT" \
./"$RUN_SCRIPT"

echo "🎉 GitLab -> ArgoCD 自动部署完成"
