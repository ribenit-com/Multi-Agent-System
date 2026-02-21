#!/bin/bash
set -euo pipefail

# ================= 配置区 =================
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"   # 必须提前 export GITLAB_PAT
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"  # ArgoCD 中的应用名

# ================= 参数检查 =================
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 错误: 请先设置 GITLAB_PAT 环境变量"
    echo "   例如: export GITLAB_PAT='ghp_xxxx'"
    exit 1
fi

# ================= 创建 ServiceAccount =================
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ================= 生成 ServiceAccount token =================
echo "🔹 生成 ServiceAccount token ..."
if ! ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null); then
    echo "⚠️ token 生成失败，尝试获取已有 secret ..."
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" | grep "${SA_NAME}-token" | head -1 | xargs -I{} kubectl get secret -n "$ARGOCD_NAMESPACE" {} -o jsonpath='{.data.token}' | base64 -d)
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ================= 添加 Git 仓库到 ArgoCD =================
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
    # 如果仓库已存在也当成功处理
    if grep -q "already exists" /tmp/repo_add_result.json; then
        echo "✅ 仓库已存在，无需重复添加"
    else
        echo "❌ 仓库添加失败 (HTTP $HTTP_CODE)"
        cat /tmp/repo_add_result.json
        exit 1
    fi
fi

# ================= 等待 ArgoCD Application 同步完成 =================
echo "🔹 等待 ArgoCD Application 同步完成 ..."
MAX_RETRIES=120   # 最多等待 10 分钟
SLEEP_SEC=5

for i in $(seq 1 $MAX_RETRIES); do
    STATUS=$(kubectl -n argocd get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n argocd get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo "[$i] sync=$STATUS, health=$HEALTH"
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ ArgoCD Application 已同步完成"
        break
    fi
    if [[ "$i" -eq "$MAX_RETRIES" ]]; then
        echo "⚠️ 超时，Application 可能未同步完成或不健康"
        exit 1
    fi
    sleep $SLEEP_SEC
done

# ================= 显示当前仓库列表 =================
echo "🔹 当前 ArgoCD 仓库列表:"
curl -sk -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/repositories" | jq -r '.items[] | "\(.name) -> \(.repo)"'

# ================= 输出 Token =================
echo "🎉 一键部署完成"
echo "💡 Token 可用于后续 CI/CD 操作:"
echo "$ARGOCD_AUTH_TOKEN"
