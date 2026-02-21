#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 一条命令式部署脚本 v1.3.0
# 功能：
#   - 下载最新部署脚本
#   - 配置 GitLab PAT
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

# ====== 2️⃣ 配置 ArgoCD 仓库凭证 ======
echo "🔹 配置 ArgoCD 仓库凭证..."
if argocd repo list | grep -q "$(basename "$REPO_URL")"; then
    argocd repo update "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT"
else
    argocd repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP"
fi

# ====== 3️⃣ 执行部署脚本 ======
echo "🔹 执行部署脚本..."
ARGO_APP="$ARGO_APP" \
ARGO_NAMESPACE="$ARGO_NAMESPACE" \
DEPLOY_NAMESPACE="$DEPLOY_NAMESPACE" \
REPO_URL="$REPO_URL" \
REPO_PATH="$REPO_PATH" \
TIMEOUT="$TIMEOUT" \
./"$RUN_SCRIPT"

echo "🎉 GitLab -> ArgoCD 部署完成"
