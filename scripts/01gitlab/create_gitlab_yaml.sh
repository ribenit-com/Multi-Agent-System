#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成核心脚本（增强版）
#########################################

VERSION="v1.0.0"

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

#########################################
# 打印执行环境信息（追踪用）
#########################################
log "===================================="
log "📌 脚本: $0"
log "📌 版本: $VERSION"
log "📌 执行用户: $(whoami)"
log "📌 当前目录: $(pwd)"
log "📌 HOME: $HOME"
log "📌 PATH: $PATH"
log "📌 Shell: $SHELL"
log "===================================="

log "▶️ 接收参数: $*"

# 读取参数
MODULE="${1:-GitLab_Test}"            
WORK_DIR="${2:-$(mktemp -d)}"         
NAMESPACE="${3:-ns-test-gitlab}"      
SECRET="${4:-sc-fast}"                
PVC_SIZE="${5:-50Gi}"                 
IMAGE="${6:-gitlab/gitlab-ce:15.0}"   
DOMAIN="${7:-gitlab.test.local}"      
IP="${8:-192.168.50.10}"              
NODEPORT_REGISTRY="${9:-35050}"
NODEPORT_SSH="${10:-30022}"
NODEPORT_HTTP="${11:-30080}"

# 确保输出目录存在
mkdir -p "$WORK_DIR"
if [ ! -d "$WORK_DIR" ]; then
    log "❌ 输出目录创建失败: $WORK_DIR"
    exit 1
fi
log "📂 输出目录: $WORK_DIR"
log "📌 当前目录文件列表: $(ls -lh "$WORK_DIR" || echo '目录为空')"

#########################################
# 写文件函数（带错误追踪）
#########################################
write_file() {
    local filename="$1"
    local content="$2"
    local filepath="$WORK_DIR/$filename"

    log "▶️ 写入文件: $filepath"
    echo "$content" > "$filepath" || { log "❌ 写入失败: $filepath"; exit 1; }

    if [ -f "$filepath" ]; then
        log "✅ 已生成 $filename (size=$(stat -c%s "$filepath") bytes)"
    else
        log "❌ 文件生成失败: $filepath"
        exit 1
    fi
}

#########################################
# 生成 YAML 文件
#########################################

# Namespace
write_file "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE"

# Secret
write_file "${MODULE}_secret.yaml" \
"apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $NAMESPACE
type: Opaque
stringData:
  root-password: \"secret123\""

# StatefulSet + PVC
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

# Service
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

# CronJob
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
            image: alpine
            command: [\"/bin/sh\", \"-c\", \"echo backup\"]
          restartPolicy: OnFailure"

#########################################
# 完成提示
#########################################
log "✅ GitLab YAML 已生成到 $WORK_DIR"
log "📌 输出目录最终文件列表: $(ls -lh "$WORK_DIR")"
