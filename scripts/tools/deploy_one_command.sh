#!/bin/bash
set -euo pipefail

ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"

if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 请设置 GITLAB_PAT 环境变量"
    exit 1
fi

# 可选：创建 ServiceAccount
SA_NAME="gitlab-deployer-sa"
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# 获取 admin 密码
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 登录 ArgoCD
argocd login "$ARGOCD_SERVER" --username admin --password "$ARGOCD_PASSWORD" --insecure --grpc-web

# 生成 token
ARGOCD_TOKEN=$(argocd account generate-token --account admin)
echo "🔹 Token 前20字符: ${ARGOCD_TOKEN:0:20} ..."

# 添加仓库
argocd repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" --insecure --grpc-web --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_TOKEN" || true

# 显示仓库
argocd repo list --server "$ARGOCD_SERVER" --grpc-web --auth-token "$ARGOCD_TOKEN"
