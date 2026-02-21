#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"
GIT_REPO_SSH="${GIT_REPO_SSH:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
APP_NAME="${APP_NAME:-gitlab-app}"
SSH_SECRET_NAME="${SSH_SECRET_NAME:-ssh-gitlab}"
GITHUB_USER="${GITHUB_USER:-ribenit-com}"
GITHUB_PAT="${GITHUB_PAT:-}"

# ===== 检查必要参数 =====
if [ -z "$ARGOCD_ADMIN_PASSWORD" ]; then
    echo "❌ 错误: 请设置 ARGOCD_ADMIN_PASSWORD 环境变量"
    exit 1
fi
if [ -z "$GITHUB_PAT" ]; then
    echo "❌ 错误: 请设置 GITHUB_PAT 环境变量"
    exit 1
fi

# ===== 创建/更新 ServiceAccount =====
echo "🔹 创建/更新 ServiceAccount gitlab-deployer-sa ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount gitlab-deployer-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding gitlab-deployer-sa-binding --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:gitlab-deployer-sa" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 SSH Key (如果不存在) =====
SSH_KEY="$HOME/.ssh/id_ed25519_argocd"
if [ ! -f "$SSH_KEY" ]; then
    echo "🔹 生成 SSH Key..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "argocd-deploy"
fi

# ===== 上传公钥到 GitHub =====
PUB_KEY=$(cat "$SSH_KEY.pub")
echo "🔹 上传公钥到 GitHub..."
curl -s -X POST \
    -H "Authorization: token $GITHUB_PAT" \
    -H "Accept: application/vnd.github+json" \
    https://api.github.com/user/keys \
    -d "{\"title\":\"argocd-deploy-$(date +%s)\",\"key\":\"$PUB_KEY\"}"

# ===== 创建/更新 ArgoCD SSH Secret =====
echo "🔹 创建/更新 ArgoCD SSH Secret: $SSH_SECRET_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic "$SSH_SECRET_NAME" \
    --from-file=sshPrivateKey="$SSH_KEY" \
    --from-file=sshPublicKey="$SSH_KEY.pub" \
    --dry-run=client -o yaml | kubectl apply -f -

# ===== 登录 ArgoCD CLI =====
echo "🔹 登录 ArgoCD CLI ..."
argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure

# ===== 添加或更新 Git 仓库 =====
echo "🔹 添加或更新 Git 仓库 $GIT_REPO_SSH ..."
if argocd repo list | grep -q "$GIT_REPO_SSH"; then
    echo "⚠️ 仓库已存在，跳过添加"
else
    argocd repo add "$GIT_REPO_SSH" --ssh-private-key-path "$SSH_KEY" --name gitlab
fi

# ===== 创建或更新 Application =====
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

# ===== 同步 Application 并轮询状态 =====
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

echo "🎉 一键 GitOps 自动部署完成"
