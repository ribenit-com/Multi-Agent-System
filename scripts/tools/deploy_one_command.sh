#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
REPO_SSH="${REPO_SSH:-git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519_argocd}"

# ===== 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" \
  --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 ServiceAccount token =====
echo "🔹 生成 ServiceAccount token ..."
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null)
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 创建 SSH Key Secret =====
echo "🔹 创建/更新 SSH Key Secret ..."
kubectl -n "$ARGOCD_NAMESPACE" create secret generic git-ssh-key \
  --from-file=sshPrivateKey="$SSH_KEY_PATH" \
  --type=kubernetes.io/ssh-auth --dry-run=client -o yaml | kubectl apply -f -

# ===== 添加 Git 仓库到 ArgoCD =====
echo "🔹 添加 Git 仓库 $REPO_SSH 到 ArgoCD ..."
if argocd --server "$ARGOCD_SERVER" \
          --auth-token "$ARGOCD_AUTH_TOKEN" \
          --insecure repo add "$REPO_SSH" \
          --ssh-private-key-secret git-ssh-key \
          --name "$ARGO_APP" 2>/dev/null; then
    echo "✅ 仓库添加成功"
else
    echo "⚠️ 仓库可能已存在，尝试更新 ..."
    argocd --server "$ARGOCD_SERVER" \
          --auth-token "$ARGOCD_AUTH_TOKEN" \
          --insecure repo update "$REPO_SSH" \
          --ssh-private-key-secret git-ssh-key \
          --name "$ARGO_APP"
fi

# ===== 显示当前仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
argocd --server "$ARGOCD_SERVER" \
       --auth-token "$ARGOCD_AUTH_TOKEN" \
       --insecure repo list

echo "🎉 一键添加仓库完成"
echo "💡 Token 可用于 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"

# ===== 可选: 等待 ArgoCD Application 同步 =====
echo "🔹 等待 ArgoCD Application $ARGO_APP 同步完成..."
for i in {1..60}; do
  STATUS=$(kubectl -n "$ARGOCD_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' || echo "")
  HEALTH=$(kubectl -n "$ARGOCD_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' || echo "")
  echo "[$i] ArgoCD sync=$STATUS, health=$HEALTH"
  if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo "✅ ArgoCD Application 已同步完成"
    break
  fi
  sleep 5
done
