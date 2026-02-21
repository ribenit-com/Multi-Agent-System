#!/bin/bash
set -euo pipefail

# ================================
# 配置（可修改输出目录）
# ================================
SCRIPT_VERSION="v1.0.0"
CREATED_TIME=$(date +"%H:%M:%S")
OUTPUT_DIR="${1:-/mnt/truenas/Gitlab_output}"   # 可传入输出目录
YAML_DIR="${OUTPUT_DIR}/yaml"
REPORT_DIR="${OUTPUT_DIR}/htmlReport"
HTML_REPORT="${REPORT_DIR}/gitlab_report.html"
LOG_FILE="${OUTPUT_DIR}/gitlab_control_$(date +%Y%m%d_%H%M%S).log"
CHECK_INTERVAL=1
MAX_WAIT=120

# 创建目录
mkdir -p "$YAML_DIR"
mkdir -p "$REPORT_DIR"

# 日志函数
log() {
    local msg="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

# Header
log "============================================"
log "🔹 GitLab 控制脚本启动"
log "版本号: $SCRIPT_VERSION"
log "创建时间: $CREATED_TIME"
log "输出目录: $OUTPUT_DIR"
log "YAML目录: $YAML_DIR"
log "HTML报告: $HTML_REPORT"
log "日志文件: $LOG_FILE"
log "============================================"

# 调用 YAML 生成脚本
YAML_SCRIPT="$(dirname "$0")/create_gitlab_yaml.sh"
if [[ ! -x "$YAML_SCRIPT" ]]; then
    log "❌ 找不到可执行的 create_gitlab_yaml.sh"
    exit 1
fi

log "▶️ 开始生成 YAML / JSON / HTML"
# 将 OUTPUT_DIR 和 YAML_DIR 传给生成脚本
"$YAML_SCRIPT" gb "$YAML_DIR" "$OUTPUT_DIR" --version "$SCRIPT_VERSION" --time "$CREATED_TIME"

log "✅ YAML / JSON / HTML 已生成"
log "📄 YAML目录: $YAML_DIR"
log "📄 输出目录: $OUTPUT_DIR"

# 轮询 HTML 报告生成
elapsed=0
while [[ ! -f "$HTML_REPORT" ]]; do
    printf "\r⏳ 等待 HTML 报告生成... 已等待 %3d 秒" "$elapsed"
    sleep "$CHECK_INTERVAL"
    elapsed=$((elapsed + CHECK_INTERVAL))
    if [[ "$elapsed" -ge "$MAX_WAIT" ]]; then
        echo
        log "❌ 超过最大等待时间 ($MAX_WAIT 秒)，HTML 报告未生成"
        exit 1
    fi
done
echo
log "✅ HTML 报告已生成: $HTML_REPORT"

# 打印 HTML 文件信息
file_size=$(stat -c%s "$HTML_REPORT")
mod_time=$(stat -c%y "$HTML_REPORT")
log "    文件大小: $file_size bytes"
log "    最后修改时间: $mod_time"

log "============================================"
log "🎉 HTML 检测与 YAML 生成流程完成"
log "============================================"
