#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="v1.1.0"
CREATED_TIME=$(date +"%H:%M:%S")

#########################################
# 必须传 MODULE
#########################################
MODULE="${1:-}"

if [[ -z "$MODULE" ]]; then
    echo "❌ 用法: $0 <MODULE>"
    exit 1
fi

#########################################
OUTPUT_DIR="/mnt/truenas/Gitlab_output"
YAML_SCRIPT_DIR="$(dirname "$0")"
YAML_SCRIPT="${YAML_SCRIPT_DIR}/create_gitlab_yaml.sh"

MODULE_CLEAN=$(echo "$MODULE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
HTML_REPORT="$OUTPUT_DIR/${MODULE_CLEAN}_info.html"

LOG_FILE="$OUTPUT_DIR/gitlab_control_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$OUTPUT_DIR"

log() {
    local msg="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

log "============================================"
log "🔹 GitLab 控制脚本启动"
log "版本号: $SCRIPT_VERSION"
log "模块: $MODULE"
log "HTML报告路径: $HTML_REPORT"
log "YAML脚本路径: $YAML_SCRIPT"
log "============================================"

#########################################
# 只传 MODULE（修复关键点）
#########################################
if [[ -x "$YAML_SCRIPT" ]]; then
    if "$YAML_SCRIPT" "$MODULE"; then
        log "✅ YAML 生成成功"
    else
        log "❌ YAML 生成失败"
        exit 1
    fi
else
    log "❌ 找不到可执行的 create_gitlab_yaml.sh"
    exit 1
fi

#########################################
# 轮询等待 HTML
#########################################
CHECK_INTERVAL=1
MAX_WAIT=120
elapsed=0

while [[ ! -f "$HTML_REPORT" ]]; do
    sleep "$CHECK_INTERVAL"
    elapsed=$((elapsed + CHECK_INTERVAL))
    if [[ "$elapsed" -ge "$MAX_WAIT" ]]; then
        log "❌ 超时：HTML 未生成"
        exit 1
    fi
done

file_size=$(stat -c%s "$HTML_REPORT")
mod_time=$(stat -c%y "$HTML_REPORT")

log "✅ HTML 报告已生成"
log "文件大小: $file_size bytes"
log "最后修改时间: $mod_time"
log "🎉 流程完成"
