#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGO_APP="${ARGO_APP:-gitlab}"
GIT_REPO="${GIT_REPO:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_argocd}"

# ===== 检查 SSH Key =====
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: SSH 私钥不存在: $SSH_KEY_PATH"
    echo "💡 可以使用 ssh-keygen 生成，例如:"
    echo "   ssh-keygen -t ed25519 -f $SSH_KEY_PATH -C 'argocd-deploy'"
    exit 1
fi

# ===== 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 ServiceAccount Token =====
echo "🔹 生成 ServiceAccount token ..."
if ! ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null); then
    # fallback
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" | grep "${SA_NAME}-token" | head -1 | xargs -I{} kubectl get secret -n "$ARGOCD_NAMESPACE" {} -o jsonpath='{.data.token}' | base64 -d)
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 创建 SSH Secret =====
SSH_SECRET_NAME="ssh-$ARGO_APP"
echo "🔹 创建/更新 ArgoCD SSH Secret: $SSH_SECRET_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic "$SSH_SECRET_NAME" \
  --from-file=sshPrivateKey="$SSH_KEY_PATH" \
  --dry-run=client -o yaml | kubectl apply -f -

# ===== 添加 Git 仓库到 ArgoCD (使用 SSH Secret) =====
echo "🔹 添加 Git 仓库 $GIT_REPO 到 ArgoCD ..."
if ! argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo add "$GIT_REPO" \
    --name "$ARGO_APP" \
    --ssh-private-key-secret "$ARGOCD_NAMESPACE/$SSH_SECRET_NAME" 2>/dev/null; then
    echo "⚠️ 仓库可能已存在或添加失败，尝试更新..."
    argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo update "$GIT_REPO" \
        --name "$ARGO_APP" \
        --ssh-private-key-secret "$ARGOCD_NAMESPACE/$SSH_SECRET_NAME"
fi

# ===== 验证仓库 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo list | grep "$ARGO_APP"

echo "🎉 Git 仓库已成功添加到 ArgoCD"
echo "💡 Token 可用于后续 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"
