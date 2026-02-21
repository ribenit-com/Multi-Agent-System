#!/bin/bash
# =============================================================
# GitLab YAML + JSON + HTML 生成脚本（固定输出目录 + 单测兼容版）
# 生成目录: /mnt/truenas/Gitlab_yaml_test_run
# =============================================================

set -euo pipefail

#########################################
# 固定目录配置
#########################################
YAML_DIR="/mnt/truenas/Gitlab_yaml_test_run"
OUTPUT_DIR="/mnt/truenas/Gitlab_yaml_test_run"

mkdir -p "$YAML_DIR"
mkdir -p "$OUTPUT_DIR"

# 全量日志
FULL_LOG="$OUTPUT_DIR/full_script.log"

# JSON / HTML 输出
JSON_FILE="$YAML_DIR/yaml_list.json"
HTML_FILE="$OUTPUT_DIR/postgres_ha_info.html"

# 输出简要信息到终端
echo "📄 全量日志文件: $FULL_LOG"
echo "📄 YAML 文件目录: $YAML_DIR"
echo "📄 输出目录: $OUTPUT_DIR"

# 重定向 stdout/stderr 到日志文件
exec 3>&1 4>&2
exec 1>>"$FULL_LOG" 2>&1

# 打开逐行跟踪
export PS4='+[$LINENO] '
set -x

#########################################
# 模块名和文件前缀
#########################################
MODULE="GitLab_Test"

#########################################
# YAML 文件生成函数
#########################################
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$YAML_DIR/$filename"
}

#########################################
# 生成 YAML 文件
#########################################
write_file "${MODULE}_namespace.yaml" "apiVersion: v1
kind: Namespace
metadata:
  name: ns-test-gitlab"

write_file "${MODULE}_secret.yaml" "apiVersion: v1
kind: Secret
metadata:
  name: sc-fast
  namespace: ns-test-gitlab
type: Opaque
stringData:
  root-password: 'secret123'"

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

write_file "${MODULE}_cronjob.yaml" "apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-backup
  namespace: ns-test-gitlab
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
# 生成 JSON 文件
#########################################
yaml_files=("$YAML_DIR"/*.yaml)
printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s . > "$JSON_FILE"

#########################################
# 生成 HTML 文件
#########################################
{
    echo "<html><head><title>GitLab YAML & JSON 状态</title></head><body>"
    echo "<h2>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</h2>"
    echo "<h3>YAML 文件目录: $YAML_DIR</h3>"
    echo "<h3>JSON 文件: $JSON_FILE</h3>"
    echo "<h3>YAML 文件列表:</h3><ul>"
    for f in "${yaml_files[@]}"; do
        echo "<li>$f (size=$(wc -c <"$f") bytes)</li>"
    done
    echo "</ul>"
    echo "<h3>JSON 内容:</h3><pre>"
    cat "$JSON_FILE"
    echo "</pre>"
    echo "</body></html>"
} > "$HTML_FILE"

# 关闭逐行跟踪
set +x

# 恢复 stdout/stderr 到终端
exec 1>&3 2>&4

#########################################
# ✅ 最终输出（单测匹配）
#########################################
echo "✅ YAML / JSON / HTML 已生成"
echo "✅ GitLab YAML 已生成到 $YAML_DIR"
echo "📄 输出目录: $OUTPUT_DIR"
echo "📄 全量日志: $FULL_LOG"
