#!/bin/bash
# =============================================================
# GitLab YAML + JSON + HTML 生成脚本 (详尽日志输出版)
# 说明：每一步执行都会记录到共享盘 LOG 文件
# =============================================================

set -euo pipefail

#########################################
# 配置路径
#########################################
MODULE="${1:-GitLab_Test}"                  # 模块名称
WORK_DIR="${WORK_DIR:-/tmp/${MODULE}_work}" # 工作目录，允许外部指定
LOG_DIR="/mnt/truenas"                      # 日志目录共享盘
HTML_FILE="${LOG_DIR}/postgres_ha_info.html" # HTML 文件输出路径
JSON_FILE="$WORK_DIR/yaml_list.json"        # JSON 文件路径
LOG_FILE="$LOG_DIR/${MODULE}_full.log"      # 详尽日志输出文件

# 创建目录
mkdir -p "$WORK_DIR"
mkdir -p "$LOG_DIR"

# 写日志函数：所有动作和注释都会写入 LOG_FILE
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

# 写文件函数
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$WORK_DIR/$filename"
    log "生成文件: $WORK_DIR/$filename ($(echo -n "$content" | wc -c) bytes)"
}

#########################################
# 生成 Namespace YAML
#########################################
log "开始生成 Namespace YAML"
write_file "${MODULE}_namespace.yaml" "apiVersion: v1
kind: Namespace
metadata:
  name: ns-test-gitlab"

#########################################
# 生成 Secret YAML
#########################################
log "开始生成 Secret YAML"
write_file "${MODULE}_secret.yaml" "apiVersion: v1
kind: Secret
metadata:
  name: sc-fast
  namespace: ns-test-gitlab
type: Opaque
stringData:
  root-password: \"secret123\""

#########################################
# 生成 StatefulSet YAML
#########################################
log "开始生成 StatefulSet YAML"
write_file "${MODULE}_statefulset.yaml" "apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: ns-test-gitlab
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
        image: gitlab/gitlab-ce:15.0
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
      accessModes: [ \"ReadWriteOnce\" ]
      resources:
        requests:
          storage: 50Gi"

#########################################
# 生成 Service YAML
#########################################
log "开始生成 Service YAML"
write_file "${MODULE}_service.yaml" "apiVersion: v1
kind: Service
metadata:
  name: gitlab-service
  namespace: ns-test-gitlab
spec:
  type: NodePort
  selector:
    app: gitlab
  ports:
  - port: 22
    nodePort: 30022
    name: ssh
  - port: 80
    nodePort: 30080
    name: http
  - port: 5005
    nodePort: 35050
    name: registry"

#########################################
# 生成 CronJob YAML
#########################################
log "开始生成 CronJob YAML"
write_file "${MODULE}_cronjob.yaml" "apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: ns-test-gitlab
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
                claimName: sc-fast"

#########################################
# 扫描生成的 YAML 文件
#########################################
log "扫描 YAML 文件..."
yaml_files=("$WORK_DIR"/*.yaml)
log "YAML 文件总数: ${#yaml_files[@]}"
for f in "${yaml_files[@]}"; do
    size=$(wc -c < "$f")
    log "文件: $f (大小: ${size} bytes)"
done

#########################################
# 生成 JSON 文件
#########################################
log "生成 JSON 文件: $JSON_FILE"
printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s . > "$JSON_FILE"

#########################################
# 生成 HTML 文件
#########################################
log "生成 HTML 文件: $HTML_FILE"
{
    echo "<html><head><title>GitLab YAML & JSON 状态</title></head><body>"
    echo "<h2>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</h2>"
    echo "<h3>工作目录: $WORK_DIR</h3>"
    echo "<h3>JSON 文件: $JSON_FILE</h3>"
    echo "<h3>YAML 文件列表:</h3><ul>"
    for f in "${yaml_files[@]}"; do
        size=$(wc -c < "$f")
        echo "<li>$f (size=${size} bytes)</li>"
    done
    echo "</ul>"
    echo "<h3>JSON 内容:</h3><pre>"
    cat "$JSON_FILE"
    echo "</pre></body></html>"
} > "$HTML_FILE"

log "全部生成完成！YAML/JSON/HTML 文件已输出到共享盘"

# 只在终端显示关键信息
echo "✅ YAML/JSON/HTML 已生成"
echo "📄 详细日志文件: $LOG_FILE"
