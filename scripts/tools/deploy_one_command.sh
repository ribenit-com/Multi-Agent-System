#!/bin/bash
set -euo pipefail

# ===== 配置 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_ADMIN_USER="${ARGOCD_ADMIN_USER:-admin}"
ARGOCD_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-}"  # 必须 export
GIT_REPO_SSH="${GIT_REPO_SSH:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
APP_NAME="${APP_NAME:-gitlab-app}"
APP_PATH="${APP_PATH:-.}"
APP_PROJECT="${APP_PROJECT:-default}"
APP_DEST_SERVER="${APP_DEST_SERVER:-https://kubernetes.default.svc}"
APP_DEST_NAMESPACE="${APP_DEST_NAMESPACE:-default}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_argocd}"

# ===== 检查参数 =====
if [ -z "$ARGOCD_ADMIN_PASSWORD" ]; then
    echo "❌ 请设置 ARGOCD_ADMIN_PASSWORD 环境变量"
    exit 1
fi

# ===== 登录 ArgoCD CLI =====
echo "🔹 登录 ArgoCD..."
argocd login "$ARGOCD_SERVER" --username "$ARGOCD_ADMIN_USER" --password "$ARGOCD_ADMIN_PASSWORD" --insecure

# ===== 添加或更新 Git 仓库 =====
echo "🔹 添加或更新 Git 仓库 $GIT_REPO_SSH ..."
if argocd repo list | grep -q "$GIT_REPO_SSH"; then
    echo "⚠️ 仓库已存在，跳过添加"
else
    argocd repo add "$GIT_REPO_SSH" --ssh-private-key-path "$SSH_KEY_PATH"
fi

# ===== 创建或更新 ArgoCD Application =====
echo "🔹 创建或更新 Application $APP_NAME ..."
if argocd app get "$APP_NAME" >/dev/null 2>&1; then
    echo "⚠️ Application 已存在，更新配置"
    argocd app set "$APP_NAME" \
        --repo "$GIT_REPO_SSH" \
        --path "$APP_PATH" \
        --dest-server "$APP_DEST_SERVER" \
        --dest-namespace "$APP_DEST_NAMESPACE" \
        --project "$APP_PROJECT"
else
    argocd app create "$APP_NAME" \
        --repo "$GIT_REPO_SSH" \
        --path "$APP_PATH" \
        --dest-server "$APP_DEST_SERVER" \
        --dest-namespace "$APP_DEST_NAMESPACE" \
        --project "$APP_PROJECT"
fi

# ===== 同步 Application 并轮询 =====
echo "🔹 同步 Application $APP_NAME 并等待完成..."
argocd app sync "$APP_NAME" || echo "⚠️ 同步命令执行完成，开始轮询检查状态"

for i in {1..60}; do
    STATUS=$(argocd app get "$APP_NAME" -o jsonpath='{.status.sync.status}' || echo "")
    HEALTH=$(argocd app get "$APP_NAME" -o jsonpath='{.status.health.status}' || echo "")
    echo "[$i] sync=$STATUS, health=$HEALTH"
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ Application 已同步完成"
        break
    fi
    sleep 5
done

# ===== 输出状态 =====
echo "🔹 当前仓库列表:"
argocd repo list
echo "🔹 Application 状态:"
argocd app get "$APP_NAME"

echo "🎉 一键部署完成"
