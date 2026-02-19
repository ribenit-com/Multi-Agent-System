#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 基础变量
############################################
NAMESPACE="n8n"
RELEASE="n8n-ha"
IMAGE="docker.io/n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
APP_NAME="n8n-ha"

# 数据库信息
DB_NAMESPACE="database"
DB_SERVICE="postgres"
DB_USER="myuser"
DB_PASS="mypassword"
DB_NAME="mydb"

LOG_DIR="/mnt/truenas"
HTML_FILE="$LOG_DIR/n8n-ha-delivery.html"

trap 'echo; echo "[FATAL] 第 $LINENO 行执行失败"; exit 1' ERR

echo "================================================="
echo "🚀 n8n HA 企业级 GitOps 自愈部署 v12.1 (Image Auto-Fix)"
echo "================================================="

############################################
# 0️⃣ Kubernetes 检查
############################################
echo "[CHECK] Kubernetes API"
kubectl version --client >/dev/null 2>&1 || true

############################################
# 1️⃣ containerd 镜像检查 + 自动修复
############################################
echo "[CHECK] containerd 镜像"

IMAGE_EXISTS_K8S=false
IMAGE_EXISTS_DEFAULT=false

if sudo ctr -n k8s.io images list 2>/dev/null | grep -q "$IMAGE"; then
  IMAGE_EXISTS_K8S=true
fi

if sudo ctr images list 2>/dev/null | grep -q "$IMAGE"; then
  IMAGE_EXISTS_DEFAULT=true
fi

if $IMAGE_EXISTS_K8S; then
  echo "[OK] 镜像已存在 (k8s.io namespace)"
elif $IMAGE_EXISTS_DEFAULT; then
  echo "[FIX] 镜像存在于 default namespace，自动导入到 k8s.io..."
  sudo ctr images export /tmp/n8n_tmp.tar "$IMAGE"
  sudo ctr -n k8s.io images import /tmp/n8n_tmp.tar
  rm -f /tmp/n8n_tmp.tar
  echo "[OK] 已同步到 k8s.io namespace"
elif [ -f "$TAR_FILE" ]; then
  echo "[INFO] 导入离线 tar 镜像..."
  sudo ctr -n k8s.io images import "$TAR_FILE"
  echo "[OK] 镜像导入完成"
else
  echo "[WARN] 未找到镜像或 tar，尝试在线拉取..."
  sudo ctr -n k8s.io image pull "$IMAGE" || echo "[WARN] 在线拉取失败"
fi

############################################
# 2️⃣ Namespace
############################################
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

############################################
# 3️⃣ Helm 部署
############################################
echo "[HELM] 安装/升级 Release"

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  helm upgrade "$RELEASE" . -n "$NAMESPACE" || \
    helm rollback "$RELEASE" 1 -n "$NAMESPACE" || true
else
  helm install "$RELEASE" . -n "$NAMESPACE" || true
fi

############################################
# 4️⃣ GitOps
############################################
echo "[GITOPS] 同步 Git"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
  cd "$REPO_ROOT"
  git add n8n-ha-chart || true
  git diff --cached --quiet || git commit -m "auto update $(date +%F-%T)" || true
  git pull --rebase origin main || true
  git push origin main || true
else
  echo "[WARN] 当前目录非 Git 仓库，跳过 GitOps"
fi

############################################
# 5️⃣ ArgoCD
############################################
if kubectl get ns argocd >/dev/null 2>&1; then
  echo "[ARGOCD] 同步 Application"

  cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $(git config --get remote.origin.url 2>/dev/null || echo "")
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
fi

############################################
# 6️⃣ 收集数据
############################################
mkdir -p "$LOG_DIR"

safe_kubectl() { kubectl "$@" 2>/dev/null || echo ""; }

N8N_SERVICE_IP=$(safe_kubectl get svc -n "$NAMESPACE" "$RELEASE" -o jsonpath='{.spec.clusterIP}')
N8N_REPLICAS=$(safe_kubectl get deploy -n "$NAMESPACE" -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].spec.replicas}')
POD_STATUS=$(safe_kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=n8n --no-headers)

############################################
# 6.5️⃣ 数据库检测
############################################
DB_HOST="$DB_SERVICE.$DB_NAMESPACE.svc.cluster.local"

DNS_STATUS="FAILED"
TCP_STATUS="FAILED"
AUTH_STATUS="FAILED"

kubectl run dns-test --rm -i --restart=Never \
  --image=busybox -n "$NAMESPACE" \
  -- nslookup "$DB_HOST" >/dev/null 2>&1 && DNS_STATUS="OK" || true

kubectl run tcp-test --rm -i --restart=Never \
  --image=busybox -n "$NAMESPACE" \
  -- nc -z "$DB_HOST" 5432 >/dev/null 2>&1 && TCP_STATUS="OK" || true

kubectl run auth-test --rm -i --restart=Never \
  --image=postgres:15 -n "$NAMESPACE" \
  -- env PGPASSWORD="$DB_PASS" \
     psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' \
     >/dev/null 2>&1 && AUTH_STATUS="OK" || true

############################################
# 7️⃣ HTML 报告
############################################
cat > "$HTML_FILE" <<EOF
<h2>n8n HA 企业交付报告 v12.1</h2>
<p>Replicas: ${N8N_REPLICAS:-N/A}</p>
<h3>数据库连通检测</h3>
<p>DNS: $DNS_STATUS</p>
<p>TCP: $TCP_STATUS</p>
<p>AUTH: $AUTH_STATUS</p>
EOF

echo
echo "📄 报告生成: $HTML_FILE"
echo "🎉 v12.1 执行完成"
