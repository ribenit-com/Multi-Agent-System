#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"  # 必须设置
GIT_REPO="${GIT_REPO:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
APP_NAME="${APP_NAME:-gitlab-app}"
APP_NAMESPACE="${APP_NAMESPACE:-default}"
APP_PATH="${APP_PATH:-.}"     
APP_SYNC_POLICY="${APP_SYNC_POLICY:-automatic}" 

if [ -z "$ARGOCD_ADMIN_PASSWORD" ]; then
    echo "❌ 请先设置 ARGOCD_ADMIN_PASSWORD"
    exit 1
fi

# ===== 1. 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 2. 创建 SSH Secret =====
SSH_SECRET_NAME="ssh-gitlab"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519_argocd"
echo "🔹 创建/更新 ArgoCD SSH Secret: $SSH_SECRET_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic "$SSH_SECRET_NAME" \
  --from-file=sshPrivateKey="$SSH_KEY_PATH" \
  --from-literal=knownHosts="$(ssh-keyscan github.com 2>/dev/null)" \
  --dry-run=client -o yaml | kubectl apply -f -

# ===== 3. 登录 ArgoCD CLI =====
echo "🔹 登录 ArgoCD CLI ..."
argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure

# ===== 4. 添加或更新 Git 仓库 =====
echo "🔹 添加或更新 Git 仓库 $GIT_REPO ..."
if ! argocd repo list | grep -q "$GIT_REPO"; then
    argocd repo add "$GIT_REPO" --ssh-private-key-path "$SSH_KEY_PATH" --insecure-ignore-host-key
else
    echo "⚠️ 仓库已存在，跳过添加"
fi

# ===== 5. 创建或更新 Application =====
echo "🔹 创建或更新 ArgoCD Application $APP_NAME ..."
if ! argocd app get "$APP_NAME" &>/dev/null; then
    argocd app create "$APP_NAME" \
        --repo "$GIT_REPO" \
        --path "$APP_PATH" \
        --dest-server https://kubernetes.default.svc \
        --dest-namespace "$APP_NAMESPACE" \
        --sync-policy "$APP_SYNC_POLICY"
else
    echo "⚠️ Application 已存在，更新仓库和路径 ..."
    argocd app set "$APP_NAME" --repo "$GIT_REPO" --path "$APP_PATH"
fi

# ===== 6. 同步并等待完成 (兼容旧版本) =====
echo "🔹 同步 Application 并等待健康状态 ..."
argocd app sync "$APP_NAME" || echo "⚠️ 同步命令执行完成，开始轮询检查状态"

for i in {1..60}; do
    STATUS=$(argocd app get "$APP_NAME" -o jsonpath='{.status.sync.status}')
    HEALTH=$(argocd app get "$APP_NAME" -o jsonpath='{.status.health.status}')
    echo "[$i] sync=$STATUS, health=$HEALTH"
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ Application 已同步完成"
        break
    fi
    sleep 5
done

echo "🎉 一键 GitOps 自动部署完成"
argocd app get "$APP_NAME"
