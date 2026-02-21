#!/bin/bash
set -euo pipefail

# ===== 配置区 =====
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
GITLAB_USER="${GITLAB_USER:-ribenit-com}"
GITLAB_PAT="${GITLAB_PAT:-}"  # 必须从环境变量传入
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
ARGO_APP="${ARGO_APP:-gitlab}"
SA_NAME="gitlab-deployer-sa"

# ===== 检查必要参数 =====
if [ -z "$GITLAB_PAT" ]; then
    echo "❌ 错误: 请设置 GITLAB_PAT 环境变量"
    echo "   例如: export GITLAB_PAT='ghp_xxxx'"
    exit 1
fi

echo "🔹 开始自动化添加仓库到 ArgoCD: $REPO_URL"

# ===== 创建 ServiceAccount 与 RoleBinding =====
kubectl -n "$ARGOCD_NAMESPACE" create serviceaccount "$SA_NAME" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$ARGOCD_NAMESPACE" create rolebinding "$SA_NAME-binding" --clusterrole=admin --serviceaccount="$ARGOCD_NAMESPACE:$SA_NAME" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
echo "✅ ServiceAccount $SA_NAME 已创建/更新"

# ===== 生成 ServiceAccount token =====
if ARGOCD_AUTH_TOKEN=$(kubectl -n "$ARGOCD_NAMESPACE" create token "$SA_NAME" --duration=8760h 2>/dev/null); then
    echo "✅ 已生成 ServiceAccount token (有效期1年)"
else
    echo "⚠️ 无法直接使用 kubectl create token，尝试 secret 方式"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-token
  namespace: ${ARGOCD_NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF
    sleep 5
    ARGOCD_AUTH_TOKEN=$(kubectl get secret -n "$ARGOCD_NAMESPACE" "${SA_NAME}-token" -o jsonpath='{.data.token}' | base64 -d)
fi

echo "🔹 Token 前20字符: ${ARGOCD_AUTH_TOKEN:0:20}..."

# ===== 添加仓库 =====
add_repo_success=false

# 方式1: CLI + token
if argocd --server "$ARGOCD_SERVER" --auth-token "$ARGOCD_AUTH_TOKEN" --insecure repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" 2>/dev/null; then
    add_repo_success=true
    echo "✅ 使用 CLI + token 成功添加仓库"
fi

# 方式2: CLI + session
if [ "$add_repo_success" = false ]; then
    echo "🔄 尝试 CLI session 方式..."
    if argocd repo add "$REPO_URL" --username "$GITLAB_USER" --password "$GITLAB_PAT" --name "$ARGO_APP" --insecure 2>/dev/null; then
        add_repo_success=true
        echo "✅ 使用 CLI session 成功添加仓库"
    fi
fi

# 方式3: REST API
if [ "$add_repo_success" = false ]; then
    echo "🔄 尝试 REST API 方式..."
    curl -sk -X POST "https://${ARGOCD_SERVER}/api/v1/repositories" \
         -H "Authorization: Bearer $ARGOCD_AUTH_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{
               \"repo\": \"$REPO_URL\",
               \"username\": \"$GITLAB_USER\",
               \"password\": \"$GITLAB_PAT\",
               \"name\": \"$ARGO_APP\",
               \"insecure\": true
             }" >/dev/null 2>&1 && add_repo_success=true && echo "✅ REST API 成功添加仓库"
fi

# ===== 验证 =====
if [ "$add_repo_success" = true ]; then
    echo "🎉 仓库已成功添加到 ArgoCD"
    echo "💡 Token 可用于 CI/CD:"
    echo "$ARGOCD_AUTH_TOKEN"
else
    echo "❌ 所有添加方式失败，请手动检查 ArgoCD 或登录 admin"
    exit 1
fi
