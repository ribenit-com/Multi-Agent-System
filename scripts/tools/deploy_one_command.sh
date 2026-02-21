#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITHUB_USER="${GITHUB_USER:-ribenit-com}"
GITHUB_PAT="${GITHUB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"

# ===== 参数检查 =====
if [ -z "$GITHUB_PAT" ]; then
    echo "❌ 请设置 GITHUB_PAT 环境变量"
    exit 1
fi

# ===== 创建 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 token =====
echo "🔹 生成 ServiceAccount token ..."
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null || true)
if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    echo "⚠️ token 生成失败，尝试读取已有 secret ..."
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" | grep "${SA_NAME}-token" | head -1 | xargs -I{} kubectl get secret -n "$ARGOCD_NAMESPACE" {} -o jsonpath='{.data.token}' | base64 -d)
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加 HTTPS 仓库 =====
echo "🔹 添加仓库 $REPO_URL 到 ArgoCD ..."
cat > /tmp/repo.json <<EOF
{
  "repo": "$REPO_URL",
  "username": "$GITHUB_USER",
  "password": "$GITHUB_PAT",
  "insecure": true
}
EOF

HTTP_CODE=$(curl -sk -o /tmp/repo_result.json -w "%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d @/tmp/repo.json \
    "https://$ARGOCD_SERVER/api/v1/repositories")

if [[ "$HTTP_CODE" -eq 200 || "$HTTP_CODE" -eq 201 ]]; then
    echo "✅ 仓库添加成功 (HTTP $HTTP_CODE)"
else
    echo "⚠️ 仓库可能已存在或添加失败 (HTTP $HTTP_CODE)，尝试更新..."
    curl -sk -X PATCH \
         -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
         -H "Content-Type: application/json" \
         -d @/tmp/repo.json \
         "https://$ARGOCD_SERVER/api/v1/repositories/$(basename "$REPO_URL" .git)"
fi

# ===== 显示仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
curl -sk -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/repositories" | jq -r '.items[] | "\(.name) -> \(.repo)"'

echo "🎉 完成一键添加仓库"
echo "💡 Token 可用于后续 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"
