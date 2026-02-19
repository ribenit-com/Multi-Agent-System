#!/bin/bash
# ===================================================
# PostgreSQL HA GitOps YAML 生成脚本（SC + PVC）
# 功能：
#   - 根据 JSON 生成 StatefulSet、Service、PVC YAML
#   - 不依赖宿主机目录
#   - 使用指定 StorageClass 动态 PV
# ===================================================

set -euo pipefail

# -----------------------------
# 配置参数
# -----------------------------
MODULE="${1:-PostgreSQL_HA}"           # 模块名
WORK_DIR="${2:-$HOME/postgres_ha_scripts/gitops/postgres-ha}"
STORAGE_CLASS_NAME="${3:-sc-ssd-high}" # SC 名称
PVC_SIZE="${4:-5Gi}"                   # PVC 容量
NAMESPACE="ns-postgres-ha"
APP_LABEL="postgres-ha"
STATEFULSET_NAME="sts-postgres-ha"
SERVICE_PRIMARY="svc-postgres-primary"
SERVICE_REPLICA="svc-postgres-replica"

mkdir -p "$WORK_DIR"

# -----------------------------
# 生成 PVC YAML（动态 PV）
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_pvc.yaml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-postgres-ha-0
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $STORAGE_CLASS_NAME
EOF

# -----------------------------
# 生成 StatefulSet YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_statefulset.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $STATEFULSET_NAME
  namespace: $NAMESPACE
spec:
  serviceName: $SERVICE_PRIMARY
  replicas: 1
  selector:
    matchLabels:
      app: $APP_LABEL
  template:
    metadata:
      labels:
        app: $APP_LABEL
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: $PVC_SIZE
      storageClassName: $STORAGE_CLASS_NAME
EOF

# -----------------------------
# 生成 Service YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_PRIMARY
  namespace: $NAMESPACE
spec:
  selector:
    app: $APP_LABEL
  ports:
    - port: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_REPLICA
  namespace: $NAMESPACE
spec:
  selector:
    app: $APP_LABEL
  ports:
    - port: 5432
EOF

echo "✅ PostgreSQL HA YAML 已生成到 $WORK_DIR"
echo "📦 PVC YAML: ${MODULE}_pvc.yaml"
echo "📦 StatefulSet YAML: ${MODULE}_statefulset.yaml"
echo "📦 Service YAML: ${MODULE}_service.yaml"
