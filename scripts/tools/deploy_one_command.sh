#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GIT_USER="${GIT_USER:-ribenit-com}"
GIT_PAT="${GIT_PAT:-}"  # GitHub/GitLab Token
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
APP_DEST_NAMESPACE="${APP_DEST_NAMESPACE:-default}"
APP_DEST_SERVER="${APP_DEST_SERVER:-https://kubernetes.default.svc}"

# ===== 检查必要参数 =====
if [ -z "$GIT_PAT" ]; then
    echo "❌ 错误: 请设置 GIT_PAT 环境变量"
    echo "   例如: export GIT_PAT='ghp_xxxx'"
    exit 1
fi

# ===== 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 禁用 SSO 或允许 ServiceAccount token =====
echo "🔹 修改 ArgoCD ConfigMap，允许 ServiceAccount token 使用..."
kubectl -n "$ARGOCD_NAMESPACE" patch configmap argocd-cm --type merge -p '{"data":{"users.anonymous.enabled":"true"}}' || true
kubectl -n "$ARGOCD_NAMESPACE" rollout restart deployment argocd-server >/dev/null
sleep 5

# ===== 生成 ServiceAccount token =====
echo "🔹 生成 ServiceAccount token ..."
if ! ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null); then
    echo "⚠️ token 生成失败，尝试获取已有 secret ..."
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" | grep "${SA_NAME}-token" | head -1 | xargs -I{} kubectl get secret -n "$ARGOCD_NAMESPACE" {} -o jsonpath='{.data.token}' | base64 -d)
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加仓库到 ArgoCD REST API =====
echo "🔹 添加仓库 $REPO_URL 到 ArgoCD ..."
cat > /tmp/repo.json <<EOF
{
  "repo": "$REPO_URL",
  "username": "$GIT_USER",
  "password": "$GIT_PAT",
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

if [[ "$HTTP_CODE" =~ 20[01] ]]; then
    echo "✅ 仓库添加成功 (HTTP $HTTP_CODE)"
else
    echo "❌ 仓库添加失败 (HTTP $HTTP_CODE)"
    cat /tmp/repo_add_result.json
    exit 1
fi

# ===== 创建 ArgoCD 应用示例 =====
echo "🔹 创建 ArgoCD 应用 $ARGO_APP ..."
cat > /tmp/app.json <<EOF
{
  "metadata": {
    "name": "$ARGO_APP",
    "namespace": "$ARGOCD_NAMESPACE"
  },
  "spec": {
    "project": "default",
    "source": {
      "repoURL": "$REPO_URL",
      "targetRevision": "HEAD",
      "path": "."
    },
    "destination": {
      "server": "$APP_DEST_SERVER",
      "namespace": "$APP_DEST_NAMESPACE"
    },
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}
EOF

HTTP_APP=$(curl -sk -o /tmp/app_create_result.json -w "%{http_code}" \
     -X POST \
     -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
     -H "Content-Type: application/json" \
     -d @/tmp/app.json \
     "https://$ARGOCD_SERVER/api/v1/applications")

if [[ "$HTTP_APP" =~ 20[01] ]]; then
    echo "✅ 应用 $ARGO_APP 创建成功 (HTTP $HTTP_APP)"
else
    echo "❌ 应用创建失败 (HTTP $HTTP_APP)"
    cat /tmp/app_create_result.json
    exit 1
fi

# ===== 显示当前 ArgoCD 仓库和应用列表 =====
echo "🔹 当前 ArgoCD 仓库列表:"
curl -sk -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/repositories" | jq -r '.items[] | "\(.name) -> \(.repo)"'

echo "🔹 当前 ArgoCD 应用列表:"
curl -sk -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" "https://$ARGOCD_SERVER/api/v1/applications" | jq -r '.items[] | "\(.metadata.name) -> \(.spec.source.repoURL)"'

echo "🎉 一键部署完成"
echo "💡 Token 可用于 CI/CD:"
echo "$ARGOCD_AUTH_TOKEN"
