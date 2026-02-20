#!/bin/bash
set -euo pipefail

MODULE="GitLab_YAML"
WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/create_gitlab_yaml.log"

# 统一日志函数
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

log "🔹 开始生成 GitLab YAML"
log "🔹 临时目录: $WORK_DIR"

# 示例：生成 Namespace YAML
NAMESPACE_FILE="$WORK_DIR/GitLab_Test_namespace.yaml"
log "📦 生成 Namespace YAML: $NAMESPACE_FILE"
cat <<EOF >"$NAMESPACE_FILE"
apiVersion: v1
kind: Namespace
metadata:
  name: gitlab-test
EOF
log "✅ Namespace YAML 已生成"

# 示例：生成 Secret YAML
SECRET_FILE="$WORK_DIR/GitLab_Test_secret.yaml"
log "📦 生成 Secret YAML: $SECRET_FILE"
cat <<EOF >"$SECRET_FILE"
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-secret
  namespace: gitlab-test
type: Opaque
stringData:
  password: "secret123"
EOF
log "✅ Secret YAML 已生成"

# 示例：生成 StatefulSet YAML
STATEFULSET_FILE="$WORK_DIR/GitLab_Test_statefulset.yaml"
log "📦 生成 StatefulSet YAML: $STATEFULSET_FILE"
cat <<EOF >"$STATEFULSET_FILE"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: gitlab-test
spec:
  replicas: 1
EOF
log "✅ StatefulSet YAML 已生成"

# 生成 Service YAML
SERVICE_FILE="$WORK_DIR/GitLab_Test_service.yaml"
log "📦 生成 Service YAML: $SERVICE_FILE"
cat <<EOF >"$SERVICE_FILE"
apiVersion: v1
kind: Service
metadata:
  name: gitlab-service
  namespace: gitlab-test
spec:
  type: ClusterIP
EOF
log "✅ Service YAML 已生成"

# 生成 CronJob YAML
CRONJOB_FILE="$WORK_DIR/GitLab_Test_cronjob.yaml"
log "📦 生成 CronJob YAML: $CRONJOB_FILE"
cat <<EOF >"$CRONJOB_FILE"
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: gitlab-test
spec:
  schedule: "0 2 * * *"
EOF
log "✅ CronJob YAML 已生成"

log "🎉 所有 YAML 生成完成，目录: $WORK_DIR"
