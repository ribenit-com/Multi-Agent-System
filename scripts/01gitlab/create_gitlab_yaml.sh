#!/bin/bash
set -euxo pipefail
# -e: 遇到错误立即退出
# -u: 未定义变量报错
# -x: 打印每条执行命令（深度调试）
# -o pipefail: 管道失败也报错

#########################################
# GitLab YAML 生成脚本（固定输出 + 深度日志 + 错误预判版）
#########################################

VERSION="v1.4.0"
LAST_MODIFIED="2026-02-21"
AUTHOR="zdl@cmaster01"

MODULE="${1:-GitLab_Test}"            
WORK_DIR="${2:-/tmp/gitlab_yaml_output}"   # 固定路径
NAMESPACE="${3:-ns-test-gitlab}"      
SECRET="${4:-sc-fast}"                
PVC_SIZE="${5:-50Gi}"                 
IMAGE="${6:-gitlab/gitlab-ce:15.0}"   
DOMAIN="${7:-gitlab.test.local}"      
IP="${8:-192.168.50.10}"              
NODEPORT_REGISTRY="${9:-35050}"
NODEPORT_SSH="${10:-30022}"
NODEPORT_HTTP="${11:-30080}"

# -----------------
# 日志函数（带时间戳）
# -----------------
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

log "===================================="
log "📌 脚本: create_gitlab_yaml.sh"
log "📌 版本: $VERSION"
log "📌 最后修改: $LAST_MODIFIED"
log "📌 作者: $AUTHOR"
log "📌 输出目录: $WORK_DIR"
log "===================================="

mkdir -p "$WORK_DIR"

# -----------------
# 写文件函数
# -----------------
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$WORK_DIR/$filename"
    log "📦 已生成 $filename (size=$(wc -c < "$WORK_DIR/$filename") bytes)"
}

# -----------------
# 生成 YAML 文件
# -----------------
log "📌 开始生成 YAML 文件..."
write_file "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE"

write_file "${MODULE}_secret.yaml" \
"apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $NAMESPACE
type: Opaque
stringData:
  root-password: \"secret123\""

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
            command:
              - /bin/sh
              - -c
              - |
                echo '执行 GitLab registry-garbage-collect'
                registry-garbage-collect /var/opt/gitlab/gitlab-rails/etc/gitlab.yml
            volumeMounts:
              - name: gitlab-data
                mountPath: /var/opt/gitlab
          restartPolicy: OnFailure
          volumes:
            - name: gitlab-data
              persistentVolumeClaim:
                claimName: $SECRET"

# -----------------
# 扫描 YAML 并生成 JSON
# -----------------
OUTPUT_JSON="$WORK_DIR/yaml_list.json"
log "📌 开始扫描 YAML 文件..."
yaml_files=()
while IFS= read -r -d '' file; do
    yaml_files+=("$file")
done < <(find "$WORK_DIR" -type f -name "*.yaml" -print0)

log "📌 YAML 文件扫描完成，总计 ${#yaml_files[@]} 个文件"

# -----------------
# 打印整齐列表（终端可见）
# -----------------
log "📄 当前生成 YAML 文件列表:"
for f in "${yaml_files[@]}"; do
    log "  $f (size=$(wc -c < "$f") bytes)"
done

# -----------------
# 生成 JSON 文件
# -----------------
if command -v jq >/dev/null 2>&1; then
    json_array=$(printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s .)
    echo "$json_array" > "$OUTPUT_JSON"
    log "✅ JSON 文件已生成: $OUTPUT_JSON"

    # 单测兼容：输出纯文本路径
    echo "$OUTPUT_JSON"

    # 深度日志：打印 JSON 内容
    log "📄 JSON 文件内容:"
    while IFS= read -r line; do
        log "  $line"
    done < "$OUTPUT_JSON"
else
    log "⚠️ jq 未安装，无法生成 JSON 文件"
    echo ""
fi

# -----------------
# 错误预判日志
# -----------------
log "⚠️ 注意：如果出现 'Output missing expected text' 错误，可能原因："
log "  1️⃣ JSON 文件路径不固定，请使用固定 WORK_DIR"
log "  2️⃣ 日志文本带时间戳或 \\n，单测匹配失败"
log "  3️⃣ YAML 文件名或 MODULE 前缀与单测预期不一致"
log "  4️⃣ CronJob / Secret / Namespace 等字段名称与单测期待值不匹配"
log "  5️⃣ jq 未安装或 JSON 文件为空"

log "✅ GitLab YAML 一体化生成完成！"
