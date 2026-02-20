#!/bin/bash
# ===================================================
# StorageClass 创建脚本（固定命名规则：sc-ssd-high）
# 功能：
#   - 创建符合 sc-ssd-high 命名规则的 StorageClass
#   - 可配置 provisioner、回收策略、绑定模式
# ===================================================

set -euo pipefail

# -----------------------------
# 固定 StorageClass 名称
# -----------------------------
STORAGE_CLASS_NAME="sc-ssd-high"

# -----------------------------
# 可配置参数
# -----------------------------
PROVISIONER="${1:-kubernetes.io/no-provisioner}"   # 默认本地 PV，可根据云环境修改
RECLAIM_POLICY="${2:-Retain}"                       # Retain / Delete
VOLUME_BINDING_MODE="${3:-WaitForFirstConsumer}"    # Immediate / WaitForFirstConsumer

echo "🔹 创建 StorageClass: $STORAGE_CLASS_NAME"
echo "  Provisioner: $PROVISIONER"
echo "  ReclaimPolicy: $RECLAIM_POLICY"
echo "  VolumeBindingMode: $VOLUME_BINDING_MODE"

# -----------------------------
# 检查是否已存在
# -----------------------------
if kubectl get storageclass "$STORAGE_CLASS_NAME" &>/dev/null; then
    echo "⚠️ StorageClass $STORAGE_CLASS_NAME 已存在，跳过创建"
    exit 0
fi

# -----------------------------
# 生成 YAML 并应用
# -----------------------------
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS_NAME
provisioner: $PROVISIONER
reclaimPolicy: $RECLAIM_POLICY
volumeBindingMode: $VOLUME_BINDING_MODE
EOF

echo "✅ StorageClass $STORAGE_CLASS_NAME 创建完成"
