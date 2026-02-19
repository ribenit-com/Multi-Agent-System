#!/bin/bash
# ===================================================
# 脚本名称: generate_postgres_ha_yaml.sh
# 功能: 根据检测 JSON 生成 PostgreSQL HA Helm Chart YAML 文件
#       - 从 stdin 接收 JSON
#       - 动态生成 Namespace / StatefulSet / Services / PVC
# ===================================================

set -e

# -----------------------------
# 配置参数（可修改）
# -----------------------------
OUTPUT_DIR="${OUTPUT_DIR:-./postgres-ha-yaml}"  # 输出目录
REPLICA_COUNT="${REPLICA_COUNT:-3}"            # 副本数 2~3
PVC_SIZE="${PVC_SIZE:-5Gi}"                     # PVC 大小
STORAGE_CLASS="${STORAGE_CLASS:-}"             # StorageClass，如果为空使用 hostPath PV

POSTGRES_USER="${POSTGRES_USER:-myuser}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-mypassword}"
POSTGRES_DB="${POSTGRES_DB:-mydb}"

# -----------------------------
# 从 stdin 读取 JSON
# -----------------------------
INPUT_JSON=$(cat)

# -----------------------------
# 根据 JSON 提取资源信息
# -----------------------------
NAMESPACE=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Namespace") | .name')
STATEFULSET=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="StatefulSet") | .name')
SERVICE_PRIMARY=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Service") | select(.name|test("primary")) | .name')
SERVICE_REPLICA=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Service") | select(.name|test("replica")) | .name')
POD_PREFIX="$STATEFULSET"

# PVC 名称列表
readarray -t PVC_NAMES <<< "$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="PVC") | .name')"

# -----------------------------
# 创建输出目录
# -----------------------------
mkdir -p "$OUTPUT_DIR"

# -----------------------------
# 生成 Namespace YAML
# -----------------------------
cat > "$OUTPUT_DIR/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF

# -----------------------------
# 生成 StatefulSet YAML
# -----------------------------
cat > "$OUTPUT_DIR/statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $STATEFULSET
  namespace: $NAMESPACE
  labels:
    app: postgres-ha
spec:
  serviceName: $SERVICE_REPLICA
  replicas: $REPLICA_COUNT
  selector:
    matchLabels:
      app: postgres-ha
  template:
    metadata:
      labels:
        app: postgres-ha
    spec:
      containers:
        - name: postgres
          image: "docker.m.daocloud.io/library/postgres:16.3"
          imagePullPolicy: IfNotPresent
          env:
            - name: POSTGRES_USER
              value: "$POSTGRES_USER"
            - name: POSTGRES_PASSWORD
              value: "$POSTGRES_PASSWORD"
            - name: POSTGRES_DB
              value: "$POSTGRES_DB"
          ports:
            - containerPort: 5432
              name: postgres
          volumeMounts:
EOF

for pvc in "${PVC_NAMES[@]}"; do
cat >> "$OUTPUT_DIR/statefulset.yaml" <<EOF
            - name: $pvc
              mountPath: /var/lib/postgresql/data
EOF
done

cat >> "$OUTPUT_DIR/statefulset.yaml" <<EOF
  volumeClaimTemplates:
EOF

for pvc in "${PVC_NAMES[@]}"; do
cat >> "$OUTPUT_DIR/statefulset.yaml" <<EOF
    - metadata:
        name: $pvc
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: $PVC_SIZE
EOF
if [ -n "$STORAGE_CLASS" ]; then
cat >> "$OUTPUT_DIR/statefulset.yaml" <<EOF
        storageClassName: $STORAGE_CLASS
EOF
fi
done

# -----------------------------
# 生成主库 Service YAML
# -----------------------------
cat > "$OUTPUT_DIR/service-primary.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_PRIMARY
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  selector:
    app: postgres-ha
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
EOF

# -----------------------------
# 生成副本 Headless Service YAML
# -----------------------------
cat > "$OUTPUT_DIR/service-replica.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_REPLICA
  namespace: $NAMESPACE
spec:
  clusterIP: None
  selector:
    app: postgres-ha
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
EOF

# -----------------------------
# 生成手动 PV（如果没有 StorageClass）
# -----------------------------
if [ -z "$STORAGE_CLASS" ]; then
  echo "=== 生成手动 PV ==="
  for i in $(seq 0 $(($REPLICA_COUNT-1))); do
    PV_NAME="postgres-pv-$i"
    mkdir -p /mnt/data/postgres-$i
    cat > "$OUTPUT_DIR/$PV_NAME.yaml" <<EOF
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
    path: /mnt/data/postgres-$i
  persistentVolumeReclaimPolicy: Retain
EOF
  done
fi

echo "✅ PostgreSQL HA YAML 文件已生成在 $OUTPUT_DIR 目录"
