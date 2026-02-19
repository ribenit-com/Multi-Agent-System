#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 基础变量
############################################
NAMESPACE="n8n"
RELEASE="n8n-ha"
IMAGE="n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
APP_NAME="n8n-ha"

############################################
# 错误捕获
############################################
trap 'echo; echo "[FATAL] 第 $LINENO 行执行失败"; exit 1' ERR

echo "================================================="
echo "🚀 n8n HA 企业级 GitOps 自愈部署 v9"
echo "================================================="

############################################
# 0️⃣ Kubernetes 检查
############################################
echo "[CHECK] Kubernetes API"
kubectl version --client || kubectl version

############################################
# 1️⃣ containerd 镜像检查
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
    echo "[ERROR] 未找到镜像 $IMAGE 或 tar"
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
# 3️⃣ Helm 部署 + 失败自动回滚
############################################
echo "[HELM] 安装/升级 Release"

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  if ! helm upgrade "$RELEASE" . -n "$NAMESPACE"; then
    echo "[HELM] 升级失败，回滚上一版本"
    helm rollback "$RELEASE" 1 -n "$NAMESPACE"
    exit 1
  fi
else
  helm install "$RELEASE" . -n "$NAMESPACE"
fi

############################################
# 4️⃣ GitOps 自愈同步
############################################
echo "[GITOPS] 同步 Git"

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

git add n8n-ha-chart || true

if ! git diff --cached --quiet; then
  git commit -m "feat: auto update n8n-ha-chart $(date +%F-%T)"
else
  echo "[GITOPS] 无变更"
fi

# 工作区脏检测
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "[GITOPS] 检测到未提交变更，自动 stash"
  git stash push -u -m auto-stash
  STASHED=1
else
  STASHED=0
fi

# 获取远程最新
git fetch origin main

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" != "$REMOTE" ]; then
  echo "[GITOPS] 执行 rebase"
  if ! git rebase origin/main; then
    echo "[ERROR] rebase 冲突，请人工处理"
    exit 1
  fi
fi

if [ "$STASHED" -eq 1 ]; then
  git stash pop || true
fi

git push origin main

############################################
# 5️⃣ ArgoCD Application
############################################
if kubectl get ns argocd >/dev/null 2>&1; then
  echo "[ARGOCD] 创建/更新 Application"

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

  echo "[ARGOCD] 等待 Healthy 状态..."

  for i in {1..30}; do
    STATUS=$(kubectl -n argocd get app $APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
    if [ "$STATUS" == "Healthy" ]; then
      echo "[ARGOCD] Application Healthy"
      break
    fi
    sleep 5
  done
fi

############################################
# 6️⃣ 等待 Pod Ready
############################################
echo "[WAIT] 等待 Pod Ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=n8n -n "$NAMESPACE" --timeout=180s || true

############################################
# 7️⃣ 诊断输出
############################################
echo
echo "================ 集群状态 ================"
kubectl get pods -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"

echo
echo "================ ArgoCD 状态 ================"
kubectl get applications -n argocd || true

echo
echo "🎉 部署完成 (v9 Production Grade)"
echo "================================================="
