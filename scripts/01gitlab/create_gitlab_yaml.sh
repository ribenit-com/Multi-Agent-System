#!/bin/bash
set -euxo pipefail
# e: 出错立即退出
# u: 未定义变量报错
# x: 打印执行的每条命令
# o pipefail: 管道命令失败时也报错

#########################################
# 配置区
#########################################
MODULE="${1:-GitLab_Test}"          # YAML 前缀
WORK_DIR="${2:-/tmp/gitlab_yaml_output}"  # 默认工作目录（固定路径方便单测）
LOG_DIR="/mnt/truenas"              # 日志与 HTML 输出目录
HTML_FILE="${LOG_DIR}/redis_ha_info.html"
NAMESPACE="${3:-ns-test-gitlab}"    # Kubernetes Namespace
SECRET="${4:-sc-fast}"              # Secret 名称
PVC_SIZE="${5:-50Gi}"               # PVC 容量
IMAGE="${6:-gitlab/gitlab-ce:15.0}" # GitLab 镜像
DOMAIN="${7:-gitlab.test.local}"    # 外部访问域名
IP="${8:-192.168.50.10}"            # 节点 IP
NODEPORT_REGISTRY="${9:-35050}"
NODEPORT_SSH="${10:-30022}"
NODEPORT_HTTP="${11:-30080}"

# 固定 JSON 文件路径
OUTPUT_JSON="$WORK_DIR/yaml_list.json"

#########################################
# 日志函数
# 带时间戳，保证每条日志可追踪
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

#########################################
# 创建工作目录和日志目录
#########################################
mkdir -p "$WORK_DIR"
mkdir -p "$LOG_DIR"

log "📌 开始生成 GitLab YAML 与 JSON，工作目录: $WORK_DIR"
log "📌 日志目录: $LOG_DIR"

#########################################
# 写文件函数
# 功能: 输出文件 + 打印日志 + 文件大小
#########################################
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$WORK_DIR/$filename"
    log "📦 已生成 $filename (size=$(wc -c < "$WORK_DIR/$filename") bytes)"
}

#########################################
# 1️⃣ 生成 YAML 文件
#########################################

log "📌 生成 Namespace YAML"
write_file "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE"

log "📌 生成 Secret YAML"
write_file "${MODULE}_secret.yaml" \
"apiVersion: v1
kind: Secret
metadata:
  name: $SECRET
  namespace: $NAMESPACE
type: Opaque
stringData:
  root-password: \"secret123\""

log "📌 生成 StatefulSet YAML"
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

log "📌 生成 Service YAML"
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

log "📌 生成 CronJob YAML"
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

#########################################
# 2️⃣ 扫描 YAML 文件，生成 JSON 文件
#########################################

log "📌 扫描 YAML 文件..."
yaml_files=()
while IFS= read -r -d '' file; do
    yaml_files+=("$file")
done < <(find "$WORK_DIR" -type f -name "*.yaml" -print0)

log "📌 YAML 文件扫描完成，总计 ${#yaml_files[@]} 个文件"

# -----------------
# 打印 YAML 文件列表 + 文件大小
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

    # 单测兼容: 纯文本输出 JSON 路径
    echo "$OUTPUT_JSON"

    # 深度日志: JSON 内容逐行打印
    log "📄 JSON 文件内容:"
    while IFS= read -r line; do
        log "  $line"
    done < "$OUTPUT_JSON"
else
    log "⚠️ jq 未安装，无法生成 JSON 文件"
fi

#########################################
# 3️⃣ 生成 HTML 文件
# HTML 用于 RGA 智能读取服务器状态
#########################################

log "📌 生成 HTML 文件: $HTML_FILE"
{
echo "<html><head><title>GitLab YAML & JSON 状态</title></head><body>"
echo "<h2>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</h2>"
echo "<h3>工作目录: $WORK_DIR</h3>"
echo "<h3>JSON 文件: $OUTPUT_JSON</h3>"
echo "<h3>YAML 文件列表:</h3>"
echo "<ul>"
for f in "${yaml_files[@]}"; do
    size=$(wc -c < "$f")
    echo "<li>$f (size=${size} bytes)</li>"
done
echo "</ul>"
echo "<h3>JSON 内容:</h3>"
echo "<pre>"
cat "$OUTPUT_JSON"
echo "</pre>"
echo "</body></html>"
} > "$HTML_FILE"

log "✅ HTML 文件已生成，可供 RGA 或智能系统读取: $HTML_FILE"

#########################################
# 4️⃣ 错误预判日志
#########################################
log "⚠️ 注意：如果单测报 'Output missing expected text'，可能原因如下："
log "  1️⃣ JSON 文件路径不固定，请使用固定 WORK_DIR"
log "  2️⃣ 日志文本带时间戳或 \\n，单测匹配失败"
log "  3️⃣ YAML 文件名或 MODULE 前缀与单测预期不一致"
log "  4️⃣ CronJob / Secret / Namespace 等字段名称与单测期待值不匹配"
log "  5️⃣ jq 未安装或 JSON 文件为空"

log "✅ GitLab YAML 一体化 + JSON + HTML 完成！"
