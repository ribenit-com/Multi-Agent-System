#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
REPO_URL="${REPO_URL:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_argocd}"

# ===== 检查 SSH Key =====
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: 找不到 SSH 私钥 $SSH_KEY_PATH"
    echo "请先生成 SSH Key 并添加到 GitHub，示例:"
    echo "  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_argocd"
    exit 1
fi

# ===== 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 ServiceAccount token =====
echo "🔹 生成 ServiceAccount token ..."
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null)
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加 SSH 仓库到 ArgoCD =====
echo "🔹 添加 Git 仓库 $REPO_URL 到 ArgoCD ..."
if argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo add "$REPO_URL" \
       --ssh-private-key-path "$SSH_KEY_PATH" \
       --name "$ARGO_APP" 2>/dev/null; then
    echo "✅ 仓库添加成功"
else
    echo "⚠️ 仓库可能已存在或添加失败，尝试更新 ..."
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo update "$REPO_URL" \
        --ssh-private-key-path "$SSH_KEY_PATH" \
        --name "$ARGO_APP"
    echo "✅ 仓库已更新"
fi

# ===== 显示仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo list

echo "🎉 一键添加仓库完成"
echo "💡 Token 可用于 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"
