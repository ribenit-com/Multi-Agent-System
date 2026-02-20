#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成核心脚本（增强 Header 版本）
#########################################

VERSION="v1.0.0"
MODIFIED="2026-02-21"
AUTHOR="zdl@cmaster01"
SCRIPT_NAME="create_gitlab_yaml.sh"

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

#########################################
# 打印详尽 Header
#########################################
log "==================================================="
log "📌 脚本名称: $SCRIPT_NAME"
log "📌 版本号: $VERSION"
log "📌 最后修改时间: $MODIFIED"
log "📌 作者: $AUTHOR"
log "📌 执行用户: $(whoami)"
log "📌 当前目录: $(pwd)"
log "📌 HOME: $HOME"
log "📌 PATH: $PATH"
log "📌 Shell: $SHELL"
log "==================================================="

# 读取参数
MODULE="${1:-GitLab_Test}"            
WORK_DIR="${2:-$(mktemp -d)}"         
NAMESPACE="${3:-ns-test-gitlab}"      
SECRET="${4:-sc-fast}"                
PVC_SIZE="${5:-50Gi}"                 
IMAGE="${6:-gitlab/gitlab-ce:15.0}"   
DOMAIN="${7:-gitlab.test.local}"      
IP="${8:-192.168.50.10}"              
NODEPORT_REGISTRY="${9:-35050}"
NODEPORT_SSH="${10:-30022}"
NODEPORT_HTTP="${11:-30080}"

log "▶️ 接收参数: $*"

mkdir -p "$WORK_DIR"
if [ ! -d "$WORK_DIR" ]; then
    log "❌ 输出目录创建失败: $WORK_DIR"
    exit 1
fi
log "📂 输出目录: $WORK_DIR"
log "📌 当前目录文件列表: $(ls -lh "$WORK_DIR" || echo '目录为空')"
