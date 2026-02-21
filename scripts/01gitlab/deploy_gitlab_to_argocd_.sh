#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署脚本（改写版 v1.1.0）
# 功能：
#   - 从 gitlab-gitops 仓库同步 YAML
#   - 自动创建 Namespace
#   - 循环检查 ArgoCD 应用状态 + Pod Ready 状态
# ===================================================
set -euo pipefail

# -----------------------------
# 可配置变量
# -----------------------------
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
TIMEOUT="${TIMEOUT:-900}"    # 等待 15 分钟
REPO_URL="${REPO_URL:-https://gitlab.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
REPO_PATH="${REPO_PATH:-gitlab-gitops}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-ns-gitlab-ha}"

echo "🔹 部署脚本版本: v1.1.0"
echo "🔹 ArgoCD 应用: $ARGO_APP"
echo "🔹 ArgoCD Namespace: $ARGO_NAMESPACE"
echo "🔹 Git 仓库: $REPO_URL"
echo "🔹 仓库路径: $REPO_PATH"
echo "🔹 GitLab 部署 Namespace: $DEPLOY_NAMESPACE"

# -----------------------------
# 检查 ArgoCD Namespace
# -----------------------------
if ! kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ArgoCD namespace '$ARGO_NAMESPACE' 不存在"
    exit 1
fi

# -----------------------------
# 检查部署 Namespace
# -----------------------------
if ! kubectl get ns "$DEPLOY_NAMESPACE" >/dev/null 2>&1; then
    echo "🔹 创建部署命名空间: $DEPLOY_NAMESPACE"
    kubectl create ns "$DEPLOY_NAMESPACE"
fi

# -----------------------------
# 创建或更新 ArgoCD Application
# -----------------------------
cat <<EOF | kubectl apply -n "$ARGO_NAMESPACE" -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP
  namespace: $ARGO_NAMESPACE
spec:
  project: default
  source:
    repoURL: '$REPO_URL'
    path: '$REPO_PATH'
    targetRevision: 'main'
  destination:
    server: https://kubernetes.default.svc
    namespace: $DEPLOY_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "🔹 ArgoCD Application 已创建/更新"

# -----------------------------
# 等待同步完成
# -----------------------------
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    # 检查 Pod Ready
    PODS=$(kubectl get pods -n "$DEPLOY_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"="}{.status.containerStatuses[0].ready}{" "}{end}' 2>/dev/null || echo "")
    
    echo "⏱ 状态: $STATUS | 健康: $HEALTH | Pod Ready: $PODS"
    
    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
        READY_COUNT=$(echo "$PODS" | grep "=true" | wc -l)
        TOTAL_COUNT=$(echo "$PODS" | wc -w)
        if [[ "$READY_COUNT" -eq "$TOTAL_COUNT" && "$TOTAL_COUNT" -gt 0 ]]; then
            echo "✅ ArgoCD 应用同步完成且所有 Pod Ready"
            exit 0
        fi
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "❌ ArgoCD 应用同步超时或 Pod 未就绪"
exit 1
