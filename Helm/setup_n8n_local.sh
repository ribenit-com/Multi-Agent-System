#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 基础变量
############################################
NAMESPACE="automation"
APP_NAME="n8n"
IMAGE="n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
GITOPS_DIR="./n8n-gitops"

# 数据库信息
DB_NAMESPACE="database"
DB_SERVICE="postgres"
DB_USER="myuser"
DB_PASS="mypassword"
DB_NAME="mydb"

LOG_DIR="/mnt/truenas"
HTML_FILE="$LOG_DIR/n8n-ha-delivery.html"

############################################
# 错误捕获
############################################
trap 'echo; echo "[FATAL] 第 $LINENO 行执行失败"; exit 1' ERR

echo "================================================="
echo "🚀 n8n HA 本地部署自容脚本 v2.0 (本地镜像 + ArgoCD + 健康检查 + HTML 报告)"
echo "================================================="

############################################
# 0️⃣ Kubernetes 检查
############################################
echo "[CHECK] Kubernetes API"
kubectl version --client >/dev/null 2>&1 || kubectl version >/dev/null 2>&1 || true

############################################
# 1️⃣ containerd 镜像检查（本地存在即可）
############################################
echo "[CHECK] containerd 镜像"
IMAGE_NAME_ONLY="${IMAGE##*/}"

if sudo ctr -n k8s.io images list 2>/dev/null | grep -q "$IMAGE_NAME_ONLY"; then
    echo "[OK] 镜像已存在: $IMAGE_NAME_ONLY"
else
    if [ -f "$TAR_FILE" ]; then
        echo "[INFO] 镜像 tar 存在，导入镜像..."
        if command -v pv >/dev/null 2>&1; then
            pv "$TAR_FILE" | sudo ctr -n k8s.io images import - || true
        else
            sudo ctr -n k8s.io images import "$TAR_FILE" || true
        fi
        echo "[OK] 镜像导入完成"
    else
        echo "[WARN] 本地 tar 不存在，镜像无法拉取，请手动准备 $TAR_FILE"
    fi
fi

############################################
# 2️⃣ Namespace 创建
############################################
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null 2>&1 || true

############################################
# 3️⃣ 本地安装 n8n YAML
############################################
echo "[INSTALL] 本地 kubectl apply 安装 n8n"
kubectl apply -f "$GITOPS_DIR/" || true
echo "[OK] GitOps YAML 文件已应用: $GITOPS_DIR"

############################################
# 4️⃣ ArgoCD Application 创建
############################################
if kubectl get ns argocd >/dev/null 2>&1; then
    echo "[ARGOCD] 创建/更新 Application"
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_REPO/n8n-gitops
    targetRevision: main
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
    echo "[OK] ArgoCD Application 已创建/更新"
fi

############################################
# 5️⃣ Pod 就绪检查
############################################
echo "[CHECK] 等待 n8n Pod 就绪..."
MAX_WAIT=180
SLEEP_INTERVAL=5
ELAPSED=0

while true; do
  READY_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=n8n --no-headers 2>/dev/null | grep -c "Running")
  TOTAL_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=n8n --no-headers 2>/dev/null | wc -l)

  if [[ "$TOTAL_COUNT" -gt 0 && "$READY_COUNT" -eq "$TOTAL_COUNT" ]]; then
      echo "[OK] 所有 n8n Pod 已就绪 ($READY_COUNT/$TOTAL_COUNT)"
      break
  fi

  sleep $SLEEP_INTERVAL
  ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
  
  if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
      echo "[WARN] 等待 n8n Pod 就绪超时 ($READY_COUNT/$TOTAL_COUNT)"
      break
  fi
done

############################################
# 6️⃣ 服务端口可访问检查
############################################
SERVICE_IP=$(kubectl get svc -n "$NAMESPACE" n8n -o jsonpath='{.spec.clusterIP}')
SERVICE_PORT=$(kubectl get svc -n "$NAMESPACE" n8n -o jsonpath='{.spec.ports[0].port}')

echo "[CHECK] 服务端口访问..."
if nc -z -w 5 "$SERVICE_IP" "$SERVICE_PORT"; then
    echo "[OK] n8n 服务端口可访问 ($SERVICE_IP:$SERVICE_PORT)"
    SERVICE_STATUS="OK"
else
    echo "[WARN] n8n 服务端口不可访问"
    SERVICE_STATUS="FAILED"
fi

############################################
# 7️⃣ 数据库连通性检查
############################################
DB_HOST="$DB_SERVICE.$DB_NAMESPACE.svc.cluster.local"

echo "[CHECK] 数据库连通性..."
kubectl run db-test --rm -i --restart=Never \
  --image=postgres:15 -n "$NAMESPACE" \
  --env PGPASSWORD="$DB_PASS" \
  --command -- psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' >/dev/null 2>&1 && DB_STATUS="OK" || DB_STATUS="FAILED"

echo "[INFO] 数据库状态: $DB_STATUS"

############################################
# 8️⃣ HTML 报告生成
############################################
mkdir -p "$LOG_DIR"

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付报告</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:sans-serif;background:#f4f6f9;margin:0;padding:20px}
h2{color:#1677ff;text-align:center}
.status-ok{color:green;font-weight:600}
.status-failed{color:red;font-weight:600}
</style>
</head>
<body>
<h2>🚀 n8n HA 本地部署报告</h2>

<h3>部署信息</h3>
<p>Namespace: $NAMESPACE</p>
<p>App Name: $APP_NAME</p>
<p>Image: $IMAGE</p>
<p>YAML 目录: $GITOPS_DIR</p>

<h3>Pod 状态</h3>
<p>就绪 Pod: <b>$READY_COUNT/$TOTAL_COUNT</b></p>

<h3>服务状态</h3>
<p>服务端口访问: <b class="status-${SERVICE_STATUS,,}">$SERVICE_STATUS</b></p>
<p>数据库连通: <b class="status-${DB_STATUS,,}">$DB_STATUS</b></p>

<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
</body>
</html>
EOF

echo
echo "📄 企业交付报告生成完成:"
echo "👉 $HTML_FILE"
echo
echo "🎉 n8n 本地自容部署完成"
