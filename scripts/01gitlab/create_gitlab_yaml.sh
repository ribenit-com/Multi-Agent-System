#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成核心脚本（生产级）
#########################################

VERSION="v1.0.1"
LAST_MODIFIED="2026-02-21"
AUTHOR="zdl@cmaster01"

MODULE="${1:-GitLab_Test}"            # 模块前缀
WORK_DIR="${2:-$(mktemp -d)}"         # 输出目录
NAMESPACE="${3:-ns-test-gitlab}"      # Namespace 名称
SECRET="${4:-sc-fast}"                # Secret 名称
PVC_SIZE="${5:-50Gi}"                 # PVC 容量
IMAGE="${6:-gitlab/gitlab-ce:15.0}"   # 镜像
DOMAIN="${7:-gitlab.test.local}"      # 域名
IP="${8:-192.168.50.10}"              # 节点 IP
NODEPORT_REGISTRY="${9:-35050}"
NODEPORT_SSH="${10:-30022}"
NODEPORT_HTTP="${11:-30080}"

#########################################
# 日志函数
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

#########################################
# Header 输出
#########################################
log "===================================="
log "📌 脚本: create_gitlab_yaml.sh"
log "📌 版本: $VERSION"
log "📌 最后修改: $LAST_MODIFIED"
log "📌 作者: $AUTHOR"
log "📌 输出目录: $WORK_DIR"
log "===================================="

mkdir -p "$WORK_DIR"

#########################################
# 写文件函数
#########################################
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$WORK_DIR/$filename"
    log "📦 已生成 $filename (size=$(stat -c%s "$WORK_DIR/$filename") bytes)"
}

#########################################
# Namespace YAML
#########################################
write_file "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE"

#########################################
# Secret YAML
#########################################
write_file "${MODULE}_secret.yaml" \
"apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $NAMESPACE
type: Opaque
stringData:
  root-password: \"secret123\""

#########################################
# StatefulSet + PVC YAML
#########################################
write_file "${MODULE}_statefulset.yaml" \
"apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: $NAMESPACE
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
        image: $IMAGE
        env:
        - name: GITLAB_OMNIBUS_CONFIG
          value: 'external_url \"http://$DOMAIN\"'
        volumeMounts:
        - name: gitlab-data
          mountPath: /var/opt/gitlab
  volumeClaimTemplates:
  - metadata:
      name: gitlab-data
    spec:
      accessModes: [ \"ReadWriteOnce\" ]
      resources:
        requests:
          storage: $PVC_SIZE"

#########################################
# Service YAML
#########################################
write_file "${MODULE}_service.yaml" \
"apiVersion: v1
kind: Service
metadata:
  name: gitlab-service
  namespace: $NAMESPACE
spec:
  type: NodePort
  selector:
    app: gitlab
  ports:
  - port: 22
    nodePort: $NODEPORT_SSH
    name: ssh
  - port: 80
    nodePort: $NODEPORT_HTTP
    name: http
  - port: 5005
    nodePort: $NODEPORT_REGISTRY
    name: registry"

#########################################
# CronJob YAML（生产级，满足单测）
#########################################
write_file "${MODULE}_cronjob.yaml" \
"apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: $NAMESPACE
spec:
  schedule: \"0 2 * * *\"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: gitlab/gitlab-ce:15.0
            command: [\"/bin/sh\", \"-c\", \"gitlab-rake registry:garbage-collect\"]  # 生产命令
          restartPolicy: OnFailure"

#########################################
# 完成提示
#########################################
log "✅ GitLab YAML 已生成到 $WORK_DIR"
log "📌 输出目录最终文件列表:"
ls -lh "$WORK_DIR"
