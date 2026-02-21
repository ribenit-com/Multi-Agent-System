#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署脚本（完全自包含版本）
# ===================================================
set -euo pipefail

# -----------------------------
# 可配置变量
# -----------------------------
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
TIMEOUT="${TIMEOUT:-300}"   # 等待 5 分钟
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-gitlab}"  # GitLab 部署到的命名空间

echo "🔹 ArgoCD 应用: $ARGO_APP"
echo "🔹 ArgoCD Namespace: $ARGO_NAMESPACE"
echo "🔹 GitLab 部署 Namespace: $DEPLOY_NAMESPACE"

# -----------------------------
# 检查 ArgoCD 命名空间是否存在
# -----------------------------
if ! kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ArgoCD namespace '$ARGO_NAMESPACE' 不存在"
    exit 1
fi

# -----------------------------
# 检查部署命名空间是否存在，不存在就创建
# -----------------------------
if ! kubectl get ns "$DEPLOY_NAMESPACE" >/dev/null 2>&1; then
    echo "🔹 创建部署命名空间: $DEPLOY_NAMESPACE"
    kubectl create ns "$DEPLOY_NAMESPACE"
fi

# -----------------------------
# 生成临时 YAML 文件（自包含 GitLab ArgoCD 应用）
# -----------------------------
TMP_MANIFEST=$(mktemp)
cat <<EOF > "$TMP_MANIFEST"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP
  namespace: $ARGO_NAMESPACE
spec:
  project: default
  source:
    repoURL: ''  # 空仓库，不依赖 Git
    path: ''
    targetRevision: ''
  destination:
    server: https://kubernetes.default.svc
    namespace: $DEPLOY_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
  # 自包含 GitLab Deployment
  # 这里使用 inline manifests，通过 ArgoCD 执行 kubectl apply
---
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

echo "🔹 临时 YAML 文件生成: $TMP_MANIFEST"

# -----------------------------
# 部署到 ArgoCD
# -----------------------------
kubectl apply -n "$ARGO_NAMESPACE" -f "$TMP_MANIFEST"
echo "🔹 已提交部署"

# -----------------------------
# 等待同步完成
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
