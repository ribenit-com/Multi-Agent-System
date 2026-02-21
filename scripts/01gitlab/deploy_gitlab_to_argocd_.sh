#!/bin/bash
# GitLab -> ArgoCD 部署脚本（修正版）
set -euo pipefail

ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
TIMEOUT="${TIMEOUT:-300}"   # 等待 5 分钟
MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/gitlab_app.yaml}"

echo "🔹 ArgoCD 应用: $ARGO_APP"
echo "🔹 Namespace: $ARGO_NAMESPACE"

# 检查 ArgoCD 命名空间是否存在
if ! kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ArgoCD namespace '$ARGO_NAMESPACE' 不存在"
    exit 1
fi

# 下载应用 YAML
TMP_MANIFEST=$(mktemp)
curl -sSL "$MANIFEST_URL" -o "$TMP_MANIFEST"

# 应用到 ArgoCD
kubectl apply -n "$ARGO_NAMESPACE" -f "$TMP_MANIFEST"

# 等待同步完成
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    echo "⏱ 状态: $STATUS | 健康: $HEALTH"
    
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        echo "✅ ArgoCD 应用同步完成并健康"
        exit 0
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "❌ ArgoCD 应用同步超时"
exit 1
