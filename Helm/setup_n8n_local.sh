#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="n8n"
RELEASE="n8n-ha"
IMAGE="n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
APP_NAME="n8n-ha"

echo "========================================="
echo "🚀 n8n HA 企业级 GitOps 自愈部署 v8"
echo "========================================="

############################################
# 0️⃣ Kubernetes 检查（兼容老版本）
############################################
echo "[CHECK] Kubernetes API"
if kubectl version --client >/dev/null 2>&1; then
  kubectl version --client
else
  kubectl version
fi

############################################
# 1️⃣ 镜像检查
############################################
echo "[CHECK] containerd 镜像"

if ! sudo ctr -n k8s.io images list | grep -q "$IMAGE"; then
  if [ -f "$TAR_FILE" ]; then
    echo "[INFO] 导入离线镜像..."
    if command -v pv >/dev/null 2>&1; then
      pv "$TAR_FILE" | sudo ctr -n k8s.io image import -
    else
      sudo ctr -n k8s.io image import "$TAR_FILE"
    fi
    echo "[OK] 镜像导入完成"
  else
    echo "[ERROR] 未找到镜像 $IMAGE 或 tar 文件"
    exit 1
  fi
else
  echo "[OK] 镜像已存在"
fi

############################################
# 2️⃣ Namespace
############################################
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

############################################
# 3️⃣ Helm 安装/升级
############################################
echo "[HELM] 安装或升级 Release"

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  helm upgrade "$RELEASE" . -n "$NAMESPACE"
else
  helm install "$RELEASE" . -n "$NAMESPACE"
fi

############################################
# 4️⃣ GitOps 自动同步
############################################
echo "[GITOPS] 提交 Helm Chart"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

git add n8n-ha-chart || true
git commit -m "feat: auto update n8n-ha-chart $(date +%F-%T)" || true

echo "[GITOPS] rebase 远程 main"
if ! git pull --rebase origin main; then
  echo "[ERROR] Git 冲突，请手动解决"
  exit 1
fi

echo "[GITOPS] push"
git push origin main

############################################
# 5️⃣ ArgoCD Application
############################################
if kubectl get ns argocd >/dev/null 2>&1; then
  echo "[ARGOCD] 创建或更新 Application"

  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $(git config --get remote.origin.url)
    targetRevision: main
    path: n8n-ha-chart
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

  echo "[ARGOCD] 等待同步..."
  sleep 5

  kubectl -n argocd get applications
else
  echo "[WARN] 未检测到 ArgoCD，跳过 Application 创建"
fi

############################################
# 6️⃣ 等待 Pod 就绪
############################################
echo "[WAIT] 等待 Pod Ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=n8n -n "$NAMESPACE" --timeout=180s || true

############################################
# 7️⃣ 状态输出
############################################
echo
echo "================ 集群状态 ================"
kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"

echo
echo "🎉 部署完成"
echo "========================================="
