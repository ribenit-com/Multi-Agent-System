#!/bin/bash
# ===================================================
# 多模块 Kubernetes YAML + JSON + HTML 一体化生成脚本
# 功能：
#   1️⃣ 支持任意模块 (PostgreSQL / Redis / GitLab 等)
#   2️⃣ 生成 Namespace / Secret / StatefulSet / Service / CronJob YAML
#   3️⃣ 输出 JSON 文件记录 YAML 列表
#   4️⃣ 输出 HTML 文件供共享盘 RGA/智能读取
#   5️⃣ 后台日志详尽，终端只显示关键信息
# ===================================================

set -euo pipefail

# -----------------------------
# 配置参数（可修改）
# -----------------------------
MODULE="${1:-PostgreSQL_HA}"   # 模块名
WORK_DIR="/tmp/${MODULE}_work"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/${MODULE}_info.html"
JSON_FILE="${WORK_DIR}/yaml_list.json"

# 模块特定配置
case "$MODULE" in
  PostgreSQL_HA)
    NAMESPACE="ns-postgres-ha"
    SECRET="pg-secret"
    PVC_SIZE="50Gi"
    IMAGE="postgres:16"
    NODEPORT_HTTP=30010
    NODEPORT_DB=30011
    ;;
  Redis_HA)
    NAMESPACE="ns-redis-ha"
    SECRET="redis-secret"
    PVC_SIZE="20Gi"
    IMAGE="redis:7"
    NODEPORT_HTTP=30020
    NODEPORT_REDIS=30021
    ;;
  GitLab_Test)
    NAMESPACE="ns-gitlab-test"
    SECRET="sc-fast"
    PVC_SIZE="50Gi"
    IMAGE="gitlab/gitlab-ce:15.0"
    NODEPORT_HTTP=30080
    NODEPORT_SSH=30022
    NODEPORT_REGISTRY=35050
    ;;
  *)
    echo "❌ 未知模块: $MODULE"
    exit 1
    ;;
esac

mkdir -p "$WORK_DIR" "$LOG_DIR"

# -----------------------------
# 日志函数
# -----------------------------
log_file() { 
    # 详尽日志写共享盘
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "${LOG_DIR}/${MODULE}_full.log"
}

log_console() { 
    # 终端只显示关键提示
    local msg="$1"
    echo "$msg"
}

# -----------------------------
# 写 YAML 文件函数
# -----------------------------
write_yaml() {
    local filename="$1"
    local content="$2"
    echo "$content" > "${WORK_DIR}/${filename}"
    log_file "生成 ${filename} (size=$(wc -c < ${WORK_DIR}/${filename}) bytes)"
}

# -----------------------------
# 生成 YAML 文件
# -----------------------------
log_console "📌 开始生成 $MODULE YAML 文件..."
log_file "开始生成 $MODULE YAML 文件，工作目录: ${WORK_DIR}"

# Namespace
write_yaml "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}"

# Secret
write_yaml "${MODULE}_secret.yaml" \
"apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  password: 'secret123'"

# StatefulSet
case "$MODULE" in
  PostgreSQL_HA)
    write_yaml "${MODULE}_statefulset.yaml" \
"apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  serviceName: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: ${IMAGE}
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${SECRET}
              key: password
        volumeMounts:
        - name: pg-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: pg-data
    spec:
      accessModes: [ 'ReadWriteOnce' ]
      resources:
        requests:
          storage: ${PVC_SIZE}"
    ;;
  Redis_HA)
    write_yaml "${MODULE}_statefulset.yaml" \
"apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: redis
  serviceName: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: ${IMAGE}
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ 'ReadWriteOnce' ]
      resources:
        requests:
          storage: ${PVC_SIZE}"
    ;;
  GitLab_Test)
    write_yaml "${MODULE}_statefulset.yaml" \
"apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitlab
  serviceName: gitlab
  template:
    metadata:
      labels:
        app: gitlab
    spec:
      containers:
      - name: gitlab
        image: ${IMAGE}
        env:
        - name: GITLAB_OMNIBUS_CONFIG
          value: 'external_url \"http://gitlab.test.local\"'
        volumeMounts:
        - name: gitlab-data
          mountPath: /var/opt/gitlab
  volumeClaimTemplates:
  - metadata:
      name: gitlab-data
    spec:
      accessModes: [ 'ReadWriteOnce' ]
      resources:
        requests:
          storage: ${PVC_SIZE}"
    ;;
esac

# Service
case "$MODULE" in
  PostgreSQL_HA)
    write_yaml "${MODULE}_service.yaml" \
"apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: postgres
  ports:
  - port: 5432
    nodePort: ${NODEPORT_DB}
    name: postgres
  - port: 80
    nodePort: ${NODEPORT_HTTP}
    name: http"
    ;;
  Redis_HA)
    write_yaml "${MODULE}_service.yaml" \
"apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: redis
  ports:
  - port: 6379
    nodePort: ${NODEPORT_REDIS}
    name: redis
  - port: 80
    nodePort: ${NODEPORT_HTTP}
    name: http"
    ;;
  GitLab_Test)
    write_yaml "${MODULE}_service.yaml" \
"apiVersion: v1
kind: Service
metadata:
  name: gitlab-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: gitlab
  ports:
  - port: 22
    nodePort: ${NODEPORT_SSH}
    name: ssh
  - port: 80
    nodePort: ${NODEPORT_HTTP}
    name: http
  - port: 5005
    nodePort: ${NODEPORT_REGISTRY}
    name: registry"
    ;;
esac

# CronJob（通用示例）
write_yaml "${MODULE}_cronjob.yaml" \
"apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${MODULE}-backup
  namespace: ${NAMESPACE}
spec:
  schedule: '0 2 * * *'
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: alpine
            command:
              - /bin/sh
              - -c
              - 'echo Executing backup task'
          restartPolicy: OnFailure"

# -----------------------------
# 生成 JSON 文件
# -----------------------------
yaml_files=("${WORK_DIR}/"*.yaml)
printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s . > "$JSON_FILE"
log_file "生成 JSON 文件: $JSON_FILE"

# -----------------------------
# 生成 HTML 文件
# -----------------------------
{
echo "<html><head><title>$MODULE 状态</title></head><body>"
echo "<h2>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</h2>"
echo "<h3>工作目录: $WORK_DIR</h3>"
echo "<h3>JSON 文件: $JSON_FILE</h3>"
echo "<h3>YAML 文件列表:</h3>"
echo "<ul>"
for f in "${yaml_files[@]}"; do
    size=$(wc -c < "$f")
    echo "<li>${f} (size=${size} bytes)</li>"
done
echo "</ul>"
echo "<h3>JSON 内容:</h3>"
echo "<pre>"
cat "$JSON_FILE"
echo "</pre>"
echo "</body></html>"
} > "$HTML_FILE"

log_console "✅ $MODULE YAML + JSON + HTML 已生成"
log_file "生成 HTML 文件: $HTML_FILE"
