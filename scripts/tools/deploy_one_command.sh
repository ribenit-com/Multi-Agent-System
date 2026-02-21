#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"

# ===== 检查必填 =====
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 请设置 GITLAB_PAT 环境变量"
    exit 1
fi
if [ -z "${ARGOCD_TOKEN:-}" ]; then
    echo "❌ 请设置 ARGOCD_TOKEN 环境变量 (ArgoCD API token)"
    exit 1
fi

# ===== 检查仓库是否存在 =====
EXISTING_REPO=$(argocd repo list --server "$ARGOCD_SERVER" --grpc-web --auth-token "$ARGOCD_TOKEN" \
    | awk '{print $1}' \
    | grep -w "^$ARGO_APP$" || true)

if [ -n "$EXISTING_REPO" ]; then
    echo "🔹 仓库 $ARGO_APP 已存在，更新 URL/凭证..."
    argocd repo update "$REPO_URL" \
        --username "$GITLAB_USER" \
        --password "$GITLAB_PAT" \
        --insecure \
        --grpc-web \
        --server "$ARGOCD_SERVER" \
        --auth-token "$ARGOCD_TOKEN"
else
    echo "🔹 仓库 $ARGO_APP 不存在，添加新仓库..."
    argocd repo add "$REPO_URL" \
        --username "$GITLAB_USER" \
        --password "$GITLAB_PAT" \
        --name "$ARGO_APP" \
        --insecure \
        --grpc-web \
        --server "$ARGOCD_SERVER" \
        --auth-token "$ARGOCD_TOKEN"
fi

# ===== 显示当前仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd repo list --server "$ARGOCD_SERVER" --grpc-web --auth-token "$ARGOCD_TOKEN" \
    | awk '{print $1 " -> " $2}'

echo "🎉 仓库添加/更新完成"
