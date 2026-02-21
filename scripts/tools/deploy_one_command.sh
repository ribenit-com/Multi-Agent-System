#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"

# ===== 检查必要参数 =====
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 错误: 请设置 GITLAB_PAT 环境变量"
    echo "   例如: export GITLAB_PAT='ghp_xxxx'"
    exit 1
fi

# ===== 创建 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 获取 admin 密码 =====
ADMIN_PASS=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "🔹 使用 admin 登录 ArgoCD 获取 token ..."
argocd login "$ARGOCD_SERVER" --username admin --password "$ADMIN_PASS" --insecure >/dev/null

# ===== 为 ServiceAccount 生成 ArgoCD token =====
ARGOCD_AUTH_TOKEN=$(argocd account generate-token --account "$SA_NAME")
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加仓库到 ArgoCD REST API =====
echo "🔹 添加仓库 $REPO_URL 到 ArgoCD ..."
cat > /tmp/repo.json <<EOF
{
  "repo": "$REPO_URL",
  "username": "$GITLAB_USER",
  "password": "$GITLAB_PAT",
  "name": "$ARGO_APP",
  "insecure": true
}
EOF

HTTP_CODE=$(curl -sk -o /tmp/repo_add_result.json -w "%{http_code}" \
     -X POST \
     -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
     -H "Content-Type: application/json" \
     -d @/tmp/repo.json \
     "https://$ARGOCD_SERVER/api/v1/repositories")

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
    echo "✅ 仓库添加成功 (HTTP $HTTP_CODE)"
else
    echo "❌ 仓库添加失败 (HTTP $HTTP_CODE)"
    cat /tmp/repo_add_result.json
    exit 1
fi

# ===== 显示当前 ArgoCD 仓库列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
curl -sk -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/repositories" | jq -r '.items[] | "\(.name) -> \(.repo)"'

echo "🎉 一键添加仓库完成"
echo "💡 Token 可用于后续 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"
