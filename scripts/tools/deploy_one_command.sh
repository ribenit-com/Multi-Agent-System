#!/bin/bash
set -euo pipefail

#########################################
# 配置参数
#########################################
ARGO_SERVER="${ARGO_SERVER:-192.168.1.10:30100}"
ARGO_ADMIN_USER="${ARGO_ADMIN_USER:-admin}"
ARGO_ADMIN_PASSWORD="${ARGOCD_ADMIN_PASSWORD:-jiahong565}"
ARGO_APP="${ARGO_APP:-gitlab-app}"
GIT_REPO_SSH="${GIT_REPO_SSH:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
GIT_REPO_NAME="${GIT_REPO_NAME:-gitlab}"
NAMESPACE="${NAMESPACE:-default}"
SYNC_PATH="${SYNC_PATH:-.}"

#########################################
# 1️⃣ 创建/更新 ServiceAccount
#########################################
echo "🔹 创建/更新 ServiceAccount gitlab-deployer-sa ..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab-deployer-sa
  namespace: $NAMESPACE
EOF

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: gitlab-deployer-sa-binding
  namespace: $NAMESPACE
subjects:
  - kind: ServiceAccount
    name: gitlab-deployer-sa
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
EOF

#########################################
# 2️⃣ 创建/更新 ArgoCD SSH Secret
#########################################
SSH_KEY="$HOME/.ssh/id_ed25519_argocd"
if [[ ! -f "$SSH_KEY" ]]; then
    echo "🔹 生成 SSH Key ..."
    ssh-keygen -t ed25519 -C "argocd-deploy" -f "$SSH_KEY" -N ""
fi

echo "🔹 创建/更新 ArgoCD SSH Secret: ssh-gitlab ..."
kubectl -n argocd apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ssh-gitlab
  namespace: argocd
stringData:
  sshPrivateKey: |
$(sed 's/^/    /' "$SSH_KEY")
EOF

#########################################
# 3️⃣ 登录 ArgoCD CLI
#########################################
echo "🔹 登录 ArgoCD..."
argocd login "$ARGO_SERVER" --username "$ARGO_ADMIN_USER" --password "$ARGO_ADMIN_PASSWORD" --insecure

#########################################
# 4️⃣ 添加或更新 Git 仓库
#########################################
echo "🔹 添加或更新 Git 仓库 $GIT_REPO_SSH ..."
if argocd repo list | grep -q "$GIT_REPO_SSH"; then
    echo "⚠️ 仓库已存在，跳过添加"
else
    argocd repo add "$GIT_REPO_SSH" --ssh-private-key-path "$SSH_KEY" --name "$GIT_REPO_NAME"
fi

#########################################
# 5️⃣ 创建或更新 Application
#########################################
echo "🔹 创建或更新 Application $ARGO_APP ..."
if argocd app get "$ARGO_APP" >/dev/null 2>&1; then
    echo "⚠️ Application 已存在，更新配置"
    argocd app set "$ARGO_APP" --repo "$GIT_REPO_SSH" --path "$SYNC_PATH" --dest-namespace "$NAMESPACE" --dest-server https://kubernetes.default.svc
else
    argocd app create "$ARGO_APP" \
        --repo "$GIT_REPO_SSH" \
        --path "$SYNC_PATH" \
        --dest-namespace "$NAMESPACE" \
        --dest-server https://kubernetes.default.svc \
        --sync-policy automated
fi

#########################################
# 6️⃣ 同步 Application 并等待完成
#########################################
echo "🔹 同步 Application $ARGO_APP 并等待完成..."
for i in {1..60}; do
    APP_JSON=$(argocd app get "$ARGO_APP" --output json || echo "{}")
    STATUS=$(echo "$APP_JSON" | jq -r '.status.sync.status // empty')
    HEALTH=$(echo "$APP_JSON" | jq -r '.status.health.status // empty')
    echo "[$i] sync=$STATUS, health=$HEALTH"
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ Application 同步完成"
        break
    fi
    sleep 5
done

if [[ "$STATUS" != "Synced" || "$HEALTH" != "Healthy" ]]; then
    echo "⚠️ Application 同步未完成或健康异常，请检查 ArgoCD 控制台"
fi

echo "🎉 一键部署完成"
