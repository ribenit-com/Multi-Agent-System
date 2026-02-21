#!/bin/bash
set -euo pipefail

# ================================
# GitLab 控制脚本（HTML检测 + YAML生成）
# ================================

SCRIPT_VERSION="v1.0.0"
CREATED_TIME=$(date +"%H:%M:%S")

# ----------------
# 输出目录 & HTML 路径
# ----------------
OUTPUT_DIR="/mnt/truenas/Gitlab_output"
YAML_SCRIPT_DIR="$(dirname "$0")"
YAML_SCRIPT="${YAML_SCRIPT_DIR}/create_gitlab_yaml.sh"
HTML_REPORT="$OUTPUT_DIR/postgres_ha_info.html"   # 改成生成脚本实际路径
LOG_FILE="$OUTPUT_DIR/gitlab_control_$(date +%Y%m%d_%H%M%S).log"

# 确保目录存在
mkdir -p "$OUTPUT_DIR"

# ----------------
# 日志函数
# ----------------
log() {
    local msg="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

# ----------------
# Header 输出
# ----------------
log "============================================"
log "🔹 GitLab 控制脚本启动"
log "版本号: $SCRIPT_VERSION"
log "创建时间: $CREATED_TIME"
log "HTML报告路径: $HTML_REPORT"
log "YAML脚本路径: $YAML_SCRIPT"
log "日志文件: $LOG_FILE"
log "============================================"

# ----------------
# 调用 YAML 生成功能（传递版本号和时间）
# ----------------
if [[ -x "$YAML_SCRIPT" ]]; then
    log "--------------------------------------------"
    log "🔹 开始调用 create_gitlab_yaml.sh 生成 YAML"
    log "脚本路径: $YAML_SCRIPT"
    log "--------------------------------------------"
    
    if "$YAML_SCRIPT" --version "$SCRIPT_VERSION" --time "$CREATED_TIME"; then
        log "✅ YAML 生成成功"
    else
        log "❌ YAML 生成失败"
        exit 1
    fi
else
    log "❌ 找不到可执行的 create_gitlab_yaml.sh 脚本"
    exit 1
fi

# ----------------
# 轮询等待 HTML 报告生成
# ----------------
CHECK_INTERVAL=1    # 秒
MAX_WAIT=120        # 最大等待时间（秒）
elapsed=0
log "⏳ 开始轮询 HTML 报告生成 (最多等待 $MAX_WAIT 秒)..."

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

# 打印 HTML 文件信息
file_size=$(stat -c%s "$HTML_REPORT")
mod_time=$(stat -c%y "$HTML_REPORT")
log "✅ HTML 报告已生成"
log "    文件绝对路径: $HTML_REPORT"
log "    文件大小: $file_size bytes"
log "    最后修改时间: $mod_time"

log "============================================"
log "🎉 HTML 检测与 YAML 生成流程完成"
log "============================================"
