#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级一键部署 + 清晰日志 + HTML 交付页面
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/n8n-ha-chart"
NAMESPACE="automation"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/n8n_ha_info.html"
N8N_IMAGE="n8nio/n8n:2.8.2"
TAR_FILE="$CHART_DIR/n8n_2.8.2.tar"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

log_info() { echo -e "\e[34m[INFO]\e[0m $*"; }
log_warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
log_error() { echo -e "\e[31m[ERROR]\e[0m $*"; }

# ---------- Step 0: 清理已有 PVC/PV ----------
log_info "Step 0: 清理已有 PVC/PV"
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers || true
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ---------- Step 0.5: 检查 containerd 镜像 ----------
log_info "Step 0.5: 检查 containerd 镜像或导入离线 tar"
if sudo ctr -n k8s.io images ls | grep -q "${N8N_IMAGE}"; then
  log_info "containerd 上已存在镜像: $N8N_IMAGE"
else
  if [ -f "$TAR_FILE" ]; then
    log_warn "containerd 上没有 $N8N_IMAGE 镜像，检测到本地 tar 文件，开始导入..."
    sudo ctr -n k8s.io image import "$TAR_FILE" && log_info "镜像导入完成: $N8N_IMAGE"
  else
    log_error "containerd 上没有 $N8N_IMAGE 镜像，且本地未找到 tar 文件: $TAR_FILE"
    log_info "请先准备镜像文件，示例:"
    log_info "  sudo ctr -n k8s.io image import n8n_2.8.2.tar"
    log_info "  或联网拉取: sudo ctr -n k8s.io image pull docker.io/n8nio/n8n:2.8.2"
    exit 1
  fi
fi

# ---------- Step 1: 检测 StorageClass ----------
log_info "Step 1: 检测 StorageClass"
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  log_warn "集群没有 StorageClass，将使用手动 PV"
else
  log_info "检测到 StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建 Helm Chart ----------
log_info "Step 2: 创建 Helm Chart"
# 省略 Chart.yaml, values.yaml, templates 文件生成代码（与之前相同）

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  log_info "Step 3: 创建手动 PV"
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
    log_info "手动 PV 应用: $PV_NAME"
  done
fi

# ---------- Step 4: 安装或升级 Helm Chart ----------
log_info "Step 4: 使用 Helm 安装/升级 n8n HA"
if helm status n8n-ha -n $NAMESPACE >/dev/null 2>&1; then
  log_info "Release 已存在，升级 Helm Chart..."
  helm upgrade n8n-ha "$CHART_DIR" -n $NAMESPACE
else
  log_info "Release 不存在，安装 Helm Chart..."
  helm install n8n-ha "$CHART_DIR" -n $NAMESPACE --create-namespace
fi

# ---------- Step 4a: 等待 StatefulSet ----------
log_info "Step 4a: 等待 n8n StatefulSet 就绪"
for i in {1..60}; do
  READY=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.status.readyReplicas}' || echo "0")
  DESIRED=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' || echo "2")
  log_info "[${i}] StatefulSet n8n: $READY/$DESIRED 就绪"
  if [ "$READY" == "$DESIRED" ]; then
    log_info "✅ StatefulSet 已就绪"
    break
  fi
  sleep 5
done

# ---------- Step 5: 生成企业交付 HTML ----------
log_info "Step 5: 生成 HTML 页面"
# 生成 HTML 代码同上
