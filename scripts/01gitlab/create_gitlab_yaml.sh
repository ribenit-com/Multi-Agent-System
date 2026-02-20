#!/bin/bash
# =============================================================
# GitLab YAML + JSON + HTML 生成脚本（逐行记录版）
# 每一行执行动作 + 注释都会写入共享盘日志
# =============================================================

set -euo pipefail

# 日志路径
LOG_DIR="/mnt/truenas"
LOG_FILE="$LOG_DIR/full_script.log"

# 记录终端输出简要信息
echo "📄 详尽日志会写入: $LOG_FILE"

# 自定义 PS4，记录行号和命令到日志
# 每执行一行，会把行号和执行的命令写入 $LOG_FILE
export PS4='+[$LINENO] '
exec 3>&1 4>&2               # 保存原 stdout/stderr
exec 1>>"$LOG_FILE" 2>&1     # 重定向 stdout/stderr 到日志文件

# 打开跟踪
set -x

#########################################
# 示例配置和变量
#########################################
MODULE="GitLab_Test"
WORK_DIR="/tmp/${MODULE}_work"
HTML_FILE="$LOG_DIR/postgres_ha_info.html"
JSON_FILE="$WORK_DIR/yaml_list.json"

mkdir -p "$WORK_DIR"

# YAML 文件生成函数
write_file() {
    local filename="$1"
    local content="$2"
    echo "$content" > "$WORK_DIR/$filename"
}

#########################################
# 生成 YAML 示例
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

#########################################
# 生成 JSON 文件
#########################################
yaml_files=("$WORK_DIR"/*.yaml)
printf '%s\n' "${yaml_files[@]}" | jq -R . | jq -s . > "$JSON_FILE"

#########################################
# 生成 HTML 文件
#########################################
{
    echo "<html><head><title>GitLab YAML & JSON 状态</title></head><body>"
    echo "<h2>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</h2>"
    echo "<h3>工作目录: $WORK_DIR</h3>"
    echo "<h3>JSON 文件: $JSON_FILE</h3>"
    echo "<h3>YAML 文件列表:</h3><ul>"
    for f in "${yaml_files[@]}"; do
        echo "<li>$f</li>"
    done
    echo "</ul></body></html>"
} > "$HTML_FILE"

# 关闭跟踪
set +x

# 恢复 stdout/stderr 到终端
exec 1>&3 2>&4

echo "✅ YAML/JSON/HTML 已生成"
echo "📄 详尽日志文件: $LOG_FILE"
