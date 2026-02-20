#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本（生产级一体化 + 单测兼容版）
#########################################

VERSION="v1.1.1"
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
# 日志函数（带时间戳）
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
    log "📦 已生成 $filename (size=$(wc -c < "$WORK_DIR/$filename") bytes)"
}

#########################################
# 生成 Namespace YAML
#########################################
write_file "${MODULE}_namespace.yaml" \
"apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE"

#########################################
# 生成 Secret YAML
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
# 生成 StatefulSet + PVC YAML
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
# 生成 Service YAML
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
# 生成 CronJob YAML
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
# 扫描 YAML 文件并生成 JSON
#########################################
OUTPUT_JSON="$WORK_DIR/yaml_list.json"

yaml_files=()
while IFS= read -r -d '' file; do
    yaml_files+=("$file")
done < <(find "$WORK_DIR" -type f -name "*.yaml" -print0)

# 打印整齐列表
echo "📄 当前生成 YAML 文件列表:"
for f in "${yaml_files[@]}"; do
    echo " - $f"
done

# 输出 JSON 文件
if command -v jq >/dev/null 2>&1; then
    json_array=$(printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s .)
    echo "$json_array" > "$OUTPUT_JSON"
    log "✅ JSON 文件已生成: $OUTPUT_JSON"
    # 输出纯文本路径给单测（不带时间戳）
    echo "$OUTPUT_JSON"
else
    log "⚠️ jq 未安装，无法生成 JSON 文件"
    # 兼容单测，可以输出空行避免报错
    echo ""
fi

#########################################
# 完成提示
#########################################
log "✅ GitLab YAML 一体化生成完成！"
