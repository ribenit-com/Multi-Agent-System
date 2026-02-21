#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署脚本（方案1修正版）
# ===================================================
set -euo pipefail

ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"    # ArgoCD Application 所在 namespace
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-gitlab}" # GitLab Deployment/Service namespace
TIMEOUT="${TIMEOUT:-300}"

echo "🔹 ArgoCD 应用: $ARGO_APP"
echo "🔹 ArgoCD Namespace: $ARGO_NAMESPACE"
echo "🔹 GitLab 部署 Namespace: $DEPLOY_NAMESPACE"

# -----------------------------
# 检查 ArgoCD Namespace
# -----------------------------
if ! kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ArgoCD namespace '$ARGO_NAMESPACE' 不存在"
    exit 1
fi

# -----------------------------
# 创建 GitLab Namespace
# -----------------------------
if ! kubectl get ns "$DEPLOY_NAMESPACE" >/dev/null 2>&1; then
    echo "🔹 创建部署命名空间: $DEPLOY_NAMESPACE"
    kubectl create ns "$DEPLOY_NAMESPACE"
fi

# -----------------------------
# 生成 ArgoCD Application YAML
# -----------------------------
TMP_APP=$(mktemp)
cat <<EOF > "$TMP_APP"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP
  namespace: $ARGO_NAMESPACE
spec:
  project: default
  source:
    repoURL: ''       # 空仓库，自包含
    path: ''
    targetRevision: ''
  destination:
    server: https://kubernetes.default.svc
    namespace: $DEPLOY_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "🔹 临时 ArgoCD Application YAML: $TMP_APP"

# -----------------------------
# Apply ArgoCD Application
# -----------------------------
kubectl apply -f "$TMP_APP"
echo "🔹 ArgoCD Application 已创建"

# -----------------------------
# 生成 Deployment + Service YAML (在 gitlab namespace)
# -----------------------------
TMP_DEPLOY=$(mktemp)
cat <<EOF > "$TMP_DEPLOY"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitlab
  namespace: $DEPLOY_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab
  template:
    metadata:
      labels:
        app: gitlab
    spec:
      containers:
      - name: gitlab
        image: gitlab/gitlab-ce:16.2.1-ce.0
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: gitlab
  namespace: $DEPLOY_NAMESPACE
spec:
  selector:
    app: gitlab
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF

echo "🔹 Deployment + Service YAML: $TMP_DEPLOY"

# -----------------------------
# Apply Deployment/Service
# -----------------------------
kubectl apply -f "$TMP_DEPLOY"
echo "🔹 Deployment + Service 已创建"

# -----------------------------
# 等待 ArgoCD 应用同步 + 健康检查
# -----------------------------
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
