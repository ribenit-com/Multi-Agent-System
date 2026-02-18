#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级一键部署 + HTML 交付页面
# 支持 Pod 状态可视化 + PostgreSQL 初始化
# 直接 Helm 安装，无需 ArgoCD
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/n8n-ha-chart"
NAMESPACE="automation"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/n8n_ha_info.html"

POSTGRES_SERVICE="postgres"
POSTGRES_NAMESPACE="database"
POSTGRES_USER="myuser"
POSTGRES_PASSWORD="mypassword"
POSTGRES_DB_PREFIX="n8n"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ---------- Step 1: 检测 StorageClass ----------
echo "=== Step 1: 检测 StorageClass ==="
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  echo "⚠️ 集群没有 StorageClass，将使用手动 PV"
else
  echo "✅ 检测到 StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建 Helm Chart ----------
echo "=== Step 2: 创建 Helm Chart ==="
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: n8n-ha-chart
description: "n8n Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "2.224.1"
EOF

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2
image:
  registry: n8nio
  repository: n8n
  tag: "2.224.1"
  pullPolicy: IfNotPresent

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

postgres:
  host: $POSTGRES_SERVICE.$POSTGRES_NAMESPACE.svc.cluster.local
  user: $POSTGRES_USER
  password: $POSTGRES_PASSWORD
  dbPrefix: $POSTGRES_DB_PREFIX
EOF

# 模板文件（略，可使用你原来的 statefulset.yaml / service.yaml / headless-service.yaml）

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="n8n-pv-$i"
    mkdir -p /mnt/data/n8n-$i
    cat > /tmp/$PV_NAME.yaml <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
spec:
  capacity:
    storage: $PVC_SIZE
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data/n8n-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: Helm 安装 n8n ----------
echo "=== Step 4: 使用 Helm 安装 n8n HA ==="
helm upgrade --install n8n-ha $CHART_DIR -n $NAMESPACE --create-namespace

# ---------- Step 4a: 等待 StatefulSet ----------
echo "等待 n8n StatefulSet 就绪..."
for i in {1..60}; do
  if kubectl -n $NAMESPACE get sts n8n >/dev/null 2>&1; then
    kubectl -n $NAMESPACE rollout status sts/n8n --timeout=300s && break
  else
    echo "[$i] StatefulSet n8n 尚未创建，等待 5s..."
    sleep 5
  fi
done

# ---------- Step 4b: 测试 PostgreSQL 连通性并初始化 ----------
echo "=== Step 4b: 测试 PostgreSQL 连通性并初始化数据库 ==="
DB_HOST=$(kubectl -n $POSTGRES_NAMESPACE get svc $POSTGRES_SERVICE -o jsonpath='{.spec.clusterIP}')
DB_NAME="${POSTGRES_DB_PREFIX}_$(date +%s)"
DB_INIT_STATUS="未执行"
DB_ERROR=""

for i in {1..12}; do
  echo "尝试连接 PostgreSQL ($DB_HOST)... [$i/12]"
  PGPASSWORD=$POSTGRES_PASSWORD psql -h $DB_HOST -U $POSTGRES_USER -d postgres -c "\q" >/dev/null 2>&1 && break
  sleep 5
  if [ $i -eq 12 ]; then
    DB_ERROR="⚠️ 无法连接 PostgreSQL 服务 $DB_HOST"
    echo $DB_ERROR
  fi
done

if [ -z "$DB_ERROR" ]; then
  echo "✅ PostgreSQL 可连接，开始初始化数据库 $DB_NAME"
  INIT_SQL="CREATE DATABASE $DB_NAME;"
  if PGPASSWORD=$POSTGRES_PASSWORD psql -h $DB_HOST -U $POSTGRES_USER -d postgres -c "$INIT_SQL"; then
    DB_INIT_STATUS="✅ 数据库 $DB_NAME 初始化成功"
  else
    DB_INIT_STATUS="❌ 数据库 $DB_NAME 初始化失败"
    DB_ERROR="初始化数据库失败，请检查用户权限或网络"
  fi
fi

# ---------- Step 5: 生成 HTML 页面 ----------
# ... 这里使用你之前生成 HTML 的逻辑，不变
