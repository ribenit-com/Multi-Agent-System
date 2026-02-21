#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
GIT_REPO_SSH="${GIT_REPO_SSH:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
APP_NAME="${APP_NAME:-gitlab-app}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-ssh-gitlab}"

# ===== 检查必要参数 =====
if [ -z "$ARGOCD_ADMIN_PASSWORD" ]; then
    echo "❌ 错误: 请设置 ARGOCD_ADMIN_PASSWORD 环境变量"
    echo "   例如: export ARGOCD_ADMIN_PASSWORD='你的密码'"
    exit 1
fi

echo "🔹 创建/更新 ServiceAccount gitlab-deployer-sa ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount gitlab-deployer-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding gitlab-deployer-sa-binding --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:gitlab-deployer-sa" --dry-run=client -o yaml | kubectl apply -f -

echo "🔹 创建/更新 ArgoCD SSH Secret: $SSH_SECRET_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic "$SSH_SECRET_NAME" \
    --from-file=sshPrivateKey="$HOME/.ssh/id_ed25519_argocd" \
    --from-file=sshPublicKey="$HOME/.ssh/id_ed25519_argocd.pub" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "🔹 登录 ArgoCD CLI ..."
argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure

echo "🔹 添加或更新 Git 仓库 $GIT_REPO_SSH ..."
if argocd repo list | grep -q "$GIT_REPO_SSH"; then
    echo "⚠️ 仓库已存在，跳过添加"
else
    argocd repo add "$GIT_REPO_SSH" --ssh-private-key-path "$HOME/.ssh/id_ed25519_argocd" --name gitlab
fi

echo "🔹 创建或更新 Application $APP_NAME ..."
if argocd app get "$APP_NAME" &>/dev/null; then
    echo "⚠️ Application 已存在，更新配置"
    argocd app set "$APP_NAME" --repo "$GIT_REPO_SSH" --path "." --dest-namespace default --dest-server https://kubernetes.default.svc
else
    argocd app create "$APP_NAME" \
        --repo "$GIT_REPO_SSH" \
        --path "." \
        --dest-namespace default \
        --dest-server https://kubernetes.default.svc \
        --sync-policy automated
fi

echo "🔹 同步 Application $APP_NAME 并轮询状态..."
argocd app sync "$APP_NAME" || echo "⚠️ 同步命令完成，开始轮询"

for i in {1..60}; do
    JSON=$(argocd app get "$APP_NAME" -o json)
    STATUS=$(echo "$JSON" | jq -r '.status.sync.status // ""')
    HEALTH=$(echo "$JSON" | jq -r '.status.health.status // ""')
    echo "[$i] sync=$STATUS, health=$HEALTH"
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ Application 已同步完成"
        break
    fi
    sleep 5
done

echo "🎉 一键部署完成"
