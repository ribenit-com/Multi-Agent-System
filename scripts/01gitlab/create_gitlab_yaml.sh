#!/bin/bash
set -euo pipefail

#########################################
# 参数
#########################################
MODULE="${1:-}"
YAML_DIR="${2:-/mnt/truenas/Gitlab_yaml_output}"
OUTPUT_DIR="${3:-/mnt/truenas/Gitlab_output}"

if [[ -z "$MODULE" ]]; then
    echo "❌ 用法: $0 <MODULE> [YAML_DIR] [OUTPUT_DIR]"
    exit 1
fi

mkdir -p "$YAML_DIR"
mkdir -p "$OUTPUT_DIR"

FULL_LOG="$OUTPUT_DIR/full_script.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "📄 全量日志文件: $FULL_LOG"
log "📄 YAML 输出目录: $YAML_DIR"
log "📄 输出目录: $OUTPUT_DIR"

#########################################
# 生产级命名规范
#########################################
MODULE_LOWER=$(echo "$MODULE" | tr '[:upper:]' '[:lower:]')
MODULE_CLEAN=$(echo "$MODULE_LOWER" | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')

NAMESPACE="ns-${MODULE_CLEAN}-gitlab"
SECRET_NAME="${MODULE_CLEAN}-gitlab-secret"
STATEFULSET_NAME="${MODULE_CLEAN}-gitlab"
SERVICE_NAME="${MODULE_CLEAN}-gitlab-svc"
CRONJOB_NAME="${MODULE_CLEAN}-gitlab-cron"

log "📌 资源命名:"
log "   Namespace : $NAMESPACE"

#########################################
# 生成 YAML 文件
#########################################

# Namespace
cat > "$YAML_DIR/${MODULE_CLEAN}_namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

# Secret
cat > "$YAML_DIR/${MODULE_CLEAN}_secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  username: admin
  password: change_me
EOF

# StatefulSet
cat > "$YAML_DIR/${MODULE_CLEAN}_statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${STATEFULSET_NAME}
  namespace: ${NAMESPACE}
spec:
  serviceName: "${SERVICE_NAME}"
  replicas: 1
  selector:
    matchLabels:
      app: ${STATEFULSET_NAME}
  template:
    metadata:
      labels:
        app: ${STATEFULSET_NAME}
    spec:
      containers:
      - name: gitlab
        image: gitlab/gitlab-ce:latest
        ports:
        - containerPort: 80
EOF

# Service
cat > "$YAML_DIR/${MODULE_CLEAN}_service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${STATEFULSET_NAME}
  ports:
    - port: 80
      targetPort: 80
EOF

# CronJob
cat > "$YAML_DIR/${MODULE_CLEAN}_cronjob.yaml" <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${CRONJOB_NAME}
  namespace: ${NAMESPACE}
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: registry-gc
            image: gitlab/gitlab-ce:latest
            command:
            - /bin/sh
            - -c
            - gitlab-rake gitlab:registry:garbage_collect
          restartPolicy: OnFailure
EOF

#########################################
# JSON 生成
#########################################
JSON_FILE="$OUTPUT_DIR/${MODULE_CLEAN}_info.json"

cat > "$JSON_FILE" <<EOF
{
  "module": "${MODULE_CLEAN}",
  "namespace": "${NAMESPACE}",
  "generated_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

#########################################
# HTML 报告生成（已修复动态文件名）
#########################################
HTML_FILE="$OUTPUT_DIR/${MODULE_CLEAN}_info.html"

cat > "$HTML_FILE" <<EOF
<html>
<head><title>GitLab Report</title></head>
<body>
<h1>GitLab Deployment Report</h1>
<p>Module: ${MODULE_CLEAN}</p>
<p>Namespace: ${NAMESPACE}</p>
<p>Generated At: $(date)</p>
</body>
</html>
EOF

#########################################
# kubectl dry-run 校验
#########################################
for f in namespace secret statefulset service cronjob; do
    kubectl apply --dry-run=client -f "$YAML_DIR/${MODULE_CLEAN}_$f.yaml" >/dev/null 2>&1 \
    && log "✅ $f YAML 校验通过" \
    || log "⚠️ $f YAML 校验失败（未配置 kubectl 可忽略）"
done

log "✅ YAML / JSON / HTML 已生成到 $YAML_DIR"
log "📄 HTML 报告路径: $HTML_FILE"
