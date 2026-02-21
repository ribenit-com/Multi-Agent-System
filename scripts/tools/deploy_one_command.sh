#!/bin/bash
set -euo pipefail

ARGOCD_SERVER="192.168.1.10:30100"
ARGOCD_NAMESPACE="argocd"
GITLAB_USER="ribenit-com"
GITLAB_PAT="$GITLAB_PAT"  # 从环境变量读取
REPO_URL="https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git"
ARGO_APP="gitlab"

# 创建 ServiceAccount 并生成 token
SA_NAME="gitlab-deployer-sa"
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME")
export ARGOCD_AUTH_TOKEN

echo "🔹 ArgoCD ServiceAccount token:"
echo "$ARGOCD_AUTH_TOKEN"
echo "----------------------------"

# 添加仓库到 ArgoCD via REST API
curl -k -s -X POST "https://$ARGOCD_SERVER/api/v1/repositories" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
     -d "{
       \"repo\": \"$REPO_URL\",
       \"username\": \"$GITLAB_USER\",
       \"password\": \"$GITLAB_PAT\",
       \"name\": \"$ARGO_APP\"
     }" | jq
