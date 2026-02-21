#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署脚本（自更新 + 版本号管理）
# 版本: v1.0.0
# 自动下载最新部署脚本，每次执行保证最新
# ===================================================
set -euo pipefail

# -----------------------------
# 配置变量
# -----------------------------
DEPLOY_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"
TMP_SCRIPT=$(mktemp)
CURRENT_SCRIPT="$0"

ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-gitlab}"
TIMEOUT="${TIMEOUT:-300}"

# -----------------------------
# 强制下载最新脚本
# -----------------------------
echo "🔹 检查最新部署脚本..."
curl -sSL "$DEPLOY_URL" -o "$TMP_SCRIPT"
chmod +x "$TMP_SCRIPT"

# 如果下载的脚本和当前脚本内容不同，则执行最新脚本
if ! cmp -s "$TMP_SCRIPT" "$CURRENT_SCRIPT"; then
    echo "🔹 检测到新版本部署脚本，自动执行最新版本..."
    exec "$TMP_SCRIPT" "$@"
fi

# -----------------------------
# ArgoCD Namespace & GitLab Namespace
# -----------------------------
echo "🔹 ArgoCD 应用: $ARGO_APP"
echo "🔹 ArgoCD Namespace: $ARGO_NAMESPACE"
echo "🔹 GitLab 部署 Namespace: $DEPLOY_NAMESPACE"

kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1 || { echo "❌ ArgoCD namespace 不存在"; exit 1; }
kubectl get ns "$DEPLOY_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$DEPLOY_NAMESPACE"

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
    repoURL: ''
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
kubectl apply -f "$TMP_APP"
echo "🔹 ArgoCD Application 已创建"

# -----------------------------
# 生成 Deployment + Service YAML
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

kubectl apply -n "$DEPLOY_NAMESPACE" -f "$TMP_DEPLOY"
echo "🔹 Deployment + Service 已创建"

# -----------------------------
# 等待 ArgoCD Application 同步
# -----------------------------
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo "⏱ 状态: $STATUS | 健康: $HEALTH"
    [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]] && { echo "✅ ArgoCD 应用同步完成"; exit 0; }
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "❌ ArgoCD 应用同步超时"
exit 1
