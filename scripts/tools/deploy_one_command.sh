#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_PROJECT="${ARGO_PROJECT:-default}"
DEST_NAMESPACE="${DEST_NAMESPACE:-default}"
DEST_SERVER="${DEST_SERVER:-https://kubernetes.default.svc}"

# ===== 参数检查 =====
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 错误: 请设置 GITLAB_PAT 环境变量"
    echo "   例如: export GITLAB_PAT='ghp_xxxx'"
    exit 1
fi

# ===== 创建/更新 ServiceAccount =====
SA_NAME="gitlab-deployer-sa"
echo "🔹 创建/更新 ServiceAccount $SA_NAME ..."
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f -

# ===== 生成 ServiceAccount token =====
echo "🔹 生成 ServiceAccount token ..."
ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null || true)
if [ -z "$ARGOCD_AUTH_TOKEN" ]; then
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" | grep "${SA_NAME}-token" | head -1 | xargs -I{} kubectl get secret -n "$ARGOCD_NAMESPACE" {} -o jsonpath='{.data.token}' | base64 -d)
fi
echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20} ..."

# ===== 添加仓库 =====
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
    # 如果已经存在，继续
    if grep -q "already exists" /tmp/repo_add_result.json; then
        echo "⚠️ 仓库已经存在，继续..."
    else
        echo "❌ 仓库添加失败 (HTTP $HTTP_CODE)"
        cat /tmp/repo_add_result.json
        exit 1
    fi
fi

# ===== 创建 ArgoCD 应用 =====
echo "🔹 创建/更新 ArgoCD 应用 $ARGO_APP ..."
cat > /tmp/app.json <<EOF
{
  "metadata": { "name": "$ARGO_APP", "namespace": "$ARGOCD_NAMESPACE" },
  "spec": {
    "project": "$ARGO_PROJECT",
    "source": {
      "repoURL": "$REPO_URL",
      "targetRevision": "HEAD",
      "path": "."
    },
    "destination": {
      "server": "$DEST_SERVER",
      "namespace": "$DEST_NAMESPACE"
    },
    "syncPolicy": {
      "automated": { "prune": true, "selfHeal": true },
      "syncOptions": ["CreateNamespace=true"]
    }
  }
}
EOF

HTTP_APP=$(curl -sk -o /tmp/app_result.json -w "%{http_code}" \
     -X POST \
     -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
     -H "Content-Type: application/json" \
     -d @/tmp/app.json \
     "https://$ARGOCD_SERVER/api/v1/applications")

if [ "$HTTP_APP" -eq 200 ] || [ "$HTTP_APP" -eq 201 ]; then
    echo "✅ 应用 $ARGO_APP 创建成功 (HTTP $HTTP_APP)"
else
    if grep -q "already exists" /tmp/app_result.json; then
        echo "⚠️ 应用已经存在，尝试同步..."
    else
        echo "❌ 应用创建失败 (HTTP $HTTP_APP)"
        cat /tmp/app_result.json
        exit 1
    fi
fi

# ===== 同步应用 =====
echo "🔹 同步应用 $ARGO_APP ..."
curl -sk -X POST \
     -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
     "https://$ARGOCD_SERVER/api/v1/applications/$ARGO_APP/sync" >/dev/null

echo "🎉 应用已同步完成，部署结束！"
echo "💡 Token 可用于后续 CI/CD:"
echo "$ARGOCD_AUTH_TOKEN"
