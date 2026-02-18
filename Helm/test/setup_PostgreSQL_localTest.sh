#!/bin/bash
set -e

# --------------------------
# PostgreSQL PVC 状态检查脚本
# --------------------------

NAMESPACE="database"
APP_LABEL="postgres"

echo "=== Step 1: 列出所有 PostgreSQL 相关 PVC ==="
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o wide

echo ""
echo "=== Step 2: 检查 PVC 状态 ==="
PENDING_PVCS=$(kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o jsonpath='{range .items[?(@.status.phase=="Pending")]}{.metadata.name}{"\n"}{end}')

if [ -z "$PENDING_PVCS" ]; then
  echo "✅ 所有 PVC 都已绑定，无 Pending PVC"
else
  echo "⚠️ 以下 PVC 处于 Pending 状态，需要处理："
  echo "$PENDING_PVCS"

  echo ""
  echo "=== Step 3: 检查集群 StorageClass ==="
  SC_LIST=$(kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  if [ -z "$SC_LIST" ]; then
    echo "⚠️ 集群没有 StorageClass，需要手动创建 PV 或 StorageClass"
  else
    echo "✅ 集群已有 StorageClass："
    echo "$SC_LIST"
    echo "请确认 PVC 使用的 storageClassName 是否存在于上面列表中"
  fi
fi
