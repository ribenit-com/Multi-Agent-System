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
# 6️⃣ 收集 n8n 交付数据
############################################

LOG_DIR="/mnt/truenas"
HTML_FILE="$LOG_DIR/n8n-ha-delivery.html"
mkdir -p "$LOG_DIR"

N8N_SERVICE_IP=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=n8n \
  -o jsonpath='{.items[0].spec.clusterIP}' 2>/dev/null || echo "N/A")

N8N_SERVICE_PORT=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/name=n8n \
  -o jsonpath='{.items[0].spec.ports[0].port}' 2>/dev/null || echo "5678")

N8N_REPLICAS=$(kubectl get deploy -n "$NAMESPACE" -l app.kubernetes.io/name=n8n \
  -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "N/A")

POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=n8n --no-headers 2>/dev/null || echo "")
PVC_LIST=$(kubectl get pvc -n "$NAMESPACE" 2>/dev/null || echo "无 PVC")

CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | tr '\n' ' ')
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
ARGO_STATUS=$(kubectl -n argocd get app $APP_NAME -o jsonpath='{.status.health.status}' 2>/dev/null || echo "N/A")

############################################
# 7️⃣ 生成企业级交付 HTML
############################################

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付报告</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f4f6f9}
.container {display:flex;justify-content:center;padding:40px}
.card {background:#fff;width:800px;border-radius:14px;padding:40px;box-shadow:0 15px 40px rgba(0,0,0,.08)}
h2 {text-align:center;color:#1677ff;margin-bottom:30px}
h3 {margin-top:30px;color:#333;border-bottom:1px solid #eee;padding-bottom:6px}
.info {margin:6px 0}
.label {font-weight:600;color:#444}
.value {margin-left:8px;color:#555}
pre {background:#f1f3f5;padding:14px;border-radius:8px;overflow-x:auto}
.status-running {color:green;font-weight:600}
.status-pending {color:orange;font-weight:600}
.status-failed {color:red;font-weight:600}
.footer {margin-top:40px;text-align:center;font-size:12px;color:#888}
.badge {display:inline-block;padding:4px 10px;border-radius:20px;font-size:12px;background:#e6f4ff;color:#1677ff}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🚀 n8n HA 企业级交付报告</h2>

<h3>📦 部署信息</h3>
<div class="info"><span class="label">Namespace:</span><span class="value">$NAMESPACE</span></div>
<div class="info"><span class="label">Helm Release:</span><span class="value">$RELEASE</span></div>
<div class="info"><span class="label">镜像版本:</span><span class="value">$IMAGE</span></div>
<div class="info"><span class="label">副本数:</span><span class="value">$N8N_REPLICAS</span></div>
<div class="info"><span class="label">Git Commit:</span><span class="value">$GIT_COMMIT</span></div>
<div class="info"><span class="label">ArgoCD 状态:</span><span class="value">$ARGO_STATUS</span></div>

<h3>🌐 服务访问</h3>
<div class="info"><span class="label">Service IP:</span><span class="value">$N8N_SERVICE_IP</span></div>
<div class="info"><span class="label">Service Port:</span><span class="value">$N8N_SERVICE_PORT</span></div>

<pre>
内部访问:
http://$N8N_SERVICE_IP:$N8N_SERVICE_PORT

端口转发:
kubectl -n $NAMESPACE port-forward svc/$RELEASE 5678:5678
http://localhost:5678
</pre>

<h3>📊 Pod 状态</h3>
EOF

while read -r line; do
  POD_NAME=$(echo $line | awk '{print $1}')
  STATUS=$(echo $line | awk '{print $3}')
  CLASS="status-failed"
  [[ "$STATUS" == "Running" ]] && CLASS="status-running"
  [[ "$STATUS" == "Pending" ]] && CLASS="status-pending"
  echo "<div class=\"$CLASS\">$POD_NAME : $STATUS</div>" >> "$HTML_FILE"
done <<< "$POD_STATUS"

cat >> "$HTML_FILE" <<EOF

<h3>💾 PVC 列表</h3>
<pre>$PVC_LIST</pre>

<h3>🧠 集群版本</h3>
<pre>$CLUSTER_VERSION</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')<br>
<span class="badge">Production Grade v10</span>
</div>

</div>
</div>
</body>
</html>
EOF

echo
echo "📄 企业交付报告已生成:"
echo "👉 $HTML_FILE"
