#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
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

# ===== 检查是否已登录 ArgoCD admin =====
echo "🔹 检查 ArgoCD 登录状态..."
if ! argocd context get "$ARGOCD_SERVER" >/dev/null 2>&1; then
    echo "⚠️  尚未登录 ArgoCD admin，请先执行登录命令："
    echo "   argocd login $ARGOCD_SERVER --username admin --password <ADMIN_PASS> --insecure"
    exit 1
fi

# ===== 生成 admin token =====
echo "🔹 生成 ArgoCD admin token..."
ARGOCD_AUTH_TOKEN=$(argocd account generate-token --account admin 2>/dev/null)
if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    echo "❌ admin token 生成失败，请确认已登录 ArgoCD admin"
    exit 1
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加仓库到 ArgoCD =====
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
elif [ "$HTTP_CODE" -eq 409 ]; then
    echo "✅ 仓库已存在，无需重复添加"
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
