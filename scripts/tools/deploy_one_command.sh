cat > fix_argocd_repo.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_PASS="${ARGOCD_PASS:-}"  # 需要设置admin密码
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

if [ -z "$ARGOCD_PASS" ]; then
    echo "❌ 错误: 请设置 ARGOCD_PASS 环境变量 (admin密码)"
    echo "   例如: export ARGOCD_PASS='your-admin-password'"
    exit 1
fi

echo "🔹 开始添加仓库到 ArgoCD ..."

# ===== 通过API登录获取token =====
echo "🔹 通过API登录 ArgoCD ..."
LOGIN_RESPONSE=$(curl -s -k -X POST "https://$ARGOCD_SERVER/api/v1/session" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$ARGOCD_PASS\"}")

# 提取token
ARGOCD_TOKEN=$(echo "$LOGIN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ARGOCD_TOKEN" ]; then
    echo "❌ ArgoCD 登录失败，请检查密码"
    echo "响应内容: $LOGIN_RESPONSE"
    exit 1
fi
echo "🔹 Token 前20字符: ${ARGOCD_TOKEN:0:20} ..."

# ===== 添加仓库到 ArgoCD =====
echo "🔹 添加仓库 $REPO_URL 到 ArgoCD ..."

# 创建JSON请求体
cat > /tmp/repo.json <<EOF
{
  "repo": "$REPO_URL",
  "username": "$GITLAB_USER",
  "password": "$GITLAB_PAT",
  "name": "$ARGO_APP",
  "insecure": true
}
EOF

# 发送请求
HTTP_CODE=$(curl -sk -o /tmp/repo_add_result.json -w "%{http_code}" \
     -X POST \
     -H "Authorization: Bearer $ARGOCD_TOKEN" \
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
curl -sk -H "Authorization: Bearer $ARGOCD_TOKEN" "https://$ARGOCD_SERVER/api/v1/repositories" | jq -r '.items[] | "\(.repository) -> \(.url)"' 2>/dev/null || echo "  暂无仓库或jq未安装"

echo "🎉 一键添加仓库完成"
EOF

chmod +x fix_argocd_repo.sh
