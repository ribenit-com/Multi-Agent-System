#!/bin/bash
# ===================================================
# generate_postgres_ha_yaml.sh v1.1 独立执行版
# 功能:
#   - 根据检测 JSON 生成 PostgreSQL HA GitOps YAML
#   - 支持 Primary + Replica + PVC
#   - 可配置副本数 & StorageClass
#   - 支持独立调试（没有 JSON 时自动生成模拟 JSON）
# ===================================================

set -e
set -o pipefail

# -----------------------------
# 参数设置
# -----------------------------
REPLICA_COUNT="${1:-2}"                 # 副本数，默认2
STORAGE_CLASS="${2:-}"                  # StorageClass，可为空
OUTPUT_DIR="${OUTPUT_DIR:-./gitops/postgres-ha}"
POSTGRES_USER="${POSTGRES_USER:-myuser}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-mypassword}"
POSTGRES_DB="${POSTGRES_DB:-mydb}"

mkdir -p "$OUTPUT_DIR"

# -----------------------------
# 读取 JSON 或使用模拟 JSON
# -----------------------------
if [ -t 0 ]; then
  # stdin 没有输入 -> 使用默认模拟 JSON
  INPUT_JSON='[
    {"resource_type":"Namespace","name":"ns-postgres-ha","status":"存在","app":"PostgreSQL"},
    {"resource_type":"StatefulSet","name":"sts-postgres-ha-primary","status":"不存在","app":"PostgreSQL"},
    {"resource_type":"StatefulSet","name":"sts-postgres-ha-replica","status":"不存在","app":"PostgreSQL"},
    {"resource_type":"Service","name":"svc-postgres-primary","status":"不存在","app":"PostgreSQL"},
    {"resource_type":"Service","name":"svc-postgres-replica","status":"不存在","app":"PostgreSQL"},
    {"resource_type":"PVC","name":"pvc-postgres-ha-primary-0","status":"不存在","app":"PostgreSQL"},
    {"resource_type":"PVC","name":"pvc-postgres-ha-replica-0","status":"不存在","app":"PostgreSQL"}
  ]'
else
  # 从 stdin 读取 JSON
  INPUT_JSON=$(cat)
fi

# -----------------------------
# 提取资源信息
# -----------------------------
NAMESPACE=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Namespace") | .name')
STATEFULSETS=($(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="StatefulSet") | .name'))
SERVICE_PRIMARY=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Service") | select(.name|test("primary")) | .name')
SERVICE_REPLICA=$(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="Service") | select(.name|test("replica")) | .name')
PVC_NAMES=($(echo "$INPUT_JSON" | jq -r '.[] | select(.resource_type=="PVC") | .name'))

PRIMARY_STS="${STATEFULSETS[0]}"
REPLICA_STS="${STATEFULSETS[1]}"

echo "🔹 输出目录: $OUTPUT_DIR"
echo "🔹 Namespace: $NAMESPACE"
echo "🔹 Primary StatefulSet: $PRIMARY_STS"
echo "🔹 Replica StatefulSet: $REPLICA_STS"
echo "🔹 主库 Service: $SERVICE_PRIMARY"
echo "🔹 副本 Service: $SERVICE_REPLICA"
echo "🔹 PVC: ${PVC_NAMES[*]}"

# -----------------------------
# Namespace YAML
# -----------------------------
cat > "$OUTPUT_DIR/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF

# -----------------------------
# StatefulSet YAML 模板
# -----------------------------
for STS in "$PRIMARY_STS" "$REPLICA_STS"; do
  if [[ "$STS" == "$PRIMARY_STS" ]]; then
    SERVICE="$SERVICE_PRIMARY"
    REPLICAS=1
  else
    SERVICE="$SERVICE_REPLICA"
    REPLICAS=$REPLICA_COUNT
  fi

  cat > "$OUTPUT_DIR/$STS.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $STS
  namespace: $NAMESPACE
  labels:
    app: postgres-ha
spec:
  serviceName: $SERVICE
  replicas: $REPLICAS
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

  for PVC in "${PVC_NAMES[@]}"; do
    if [[ "$STS" == *"primary"* && "$PVC" == *"primary"* ]]; then
      cat >> "$OUTPUT_DIR/$STS.yaml" <<EOF
            - name: $PVC
              mountPath: /var/lib/postgresql/data
EOF
    elif [[ "$STS" == *"replica"* && "$PVC" == *"replica"* ]]; then
      cat >> "$OUTPUT_DIR/$STS.yaml" <<EOF
            - name: $PVC
              mountPath: /var/lib/postgresql/data
EOF
    fi
  done

  cat >> "$OUTPUT_DIR/$STS.yaml" <<EOF
  volumeClaimTemplates:
EOF

  for PVC in "${PVC_NAMES[@]}"; do
    if [[ "$STS" == *"primary"* && "$PVC" == *"primary"* ]] || [[ "$STS" == *"replica"* && "$PVC" == *"replica"* ]]; then
      cat >> "$OUTPUT_DIR/$STS.yaml" <<EOF
    - metadata:
        name: $PVC
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 5Gi
EOF
      if [ -n "$STORAGE_CLASS" ]; then
        cat >> "$OUTPUT_DIR/$STS.yaml" <<EOF
        storageClassName: $STORAGE_CLASS
EOF
      fi
    fi
  done

done

# -----------------------------
# Services YAML
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
# 手动 PV（如果没有 StorageClass）
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
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data/postgres-$i
  persistentVolumeReclaimPolicy: Retain
EOF
  done
fi

echo "✅ PostgreSQL HA GitOps YAML 已生成在 $OUTPUT_DIR"
