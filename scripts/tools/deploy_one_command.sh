#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGO_APP="${ARGO_APP:-gitlab}"
GIT_REPO="git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_argocd}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-ssh-gitlab}"

# ===== 1️⃣ 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 2️⃣ 生成 SSH Secret =====
echo "🔹 创建/更新 ArgoCD SSH Secret: $SSH_SECRET_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic "$SSH_SECRET_NAME" \
    --from-file=sshPrivateKey="$SSH_KEY_PATH" \
    --dry-run=client -o yaml | kubectl apply -f -

# ===== 3️⃣ 登录 ArgoCD CLI =====
echo "🔹 登录 ArgoCD CLI ..."
argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure

# ===== 4️⃣ 添加或更新 Git 仓库 =====
echo "🔹 添加或更新 Git 仓库 $GIT_REPO ..."
if argocd repo list | grep -q "$GIT_REPO"; then
    echo "⚠️ 仓库已存在，尝试更新..."
    argocd repo update "$GIT_REPO" --ssh-private-key-path "$SSH_KEY_PATH" || true
else
    argocd repo add "$GIT_REPO" --ssh-private-key-path "$SSH_KEY_PATH" --name "$ARGO_APP"
fi

# ===== 5️⃣ 显示当前仓库 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd repo list

echo "🎉 一键部署完成"
