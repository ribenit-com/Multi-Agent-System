#!/bin/bash
set -euo pipefail

#########################################
# 配置
#########################################
SCRIPT_NAME="create_gitlab_yaml.sh"
RAW_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/create_gitlab_yaml.sh"
VERSION="v1.0.0"   # 这里可以手动更新，也可以在远程脚本中解析
WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/create_gitlab_yaml.log"

#########################################
# 日志函数
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

#########################################
# Header 输出
#########################################
log "===================================="
log "📌 脚本: $SCRIPT_NAME"
log "📌 版本: $VERSION"
log "📌 临时目录: $WORK_DIR"
log "===================================="

#########################################
# 强制下载最新脚本
#########################################
download_script() {
    local target="$WORK_DIR/$SCRIPT_NAME"
    log "⬇️ 强制下载最新脚本: $RAW_URL"
    curl -fsSL "$RAW_URL" -o "$target" || {
        log "❌ 下载失败，请检查网络或 URL"
        exit 1
    }
    chmod +x "$target"
    log "✅ 下载完成并已赋予执行权限: $target"
    echo "$target"
}

SCRIPT_PATH=$(download_script)

#########################################
# 执行核心脚本
#########################################
log "▶️ 执行核心脚本: $SCRIPT_PATH"
# 如果核心脚本本身需要参数，可以在这里传入，例如: $SCRIPT_PATH arg1 arg2
bash "$SCRIPT_PATH" "$WORK_DIR"

log "🎉 脚本执行完成，所有 YAML 文件在: $WORK_DIR"
