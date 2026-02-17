#!/bin/bash
# ====================================================================
# 🤖 ClusterGate - 企业级集群端口健康检测
# 强制输出到 NAS
# ====================================================================

set -euo pipefail

# ---------------- 配置 ----------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CONTROL_IP=$(hostname -I | awk '{print $1}')

# NAS 挂载路径
NAS_LOG_DIR="/mnt/truenas"

if [ ! -d "$NAS_LOG_DIR" ]; then
    echo "❌ NAS路径 $NAS_LOG_DIR 不存在，请先挂载 NAS"
    exit 1
fi
if [ ! -w "$NAS_LOG_DIR" ]; then
    echo "❌ NAS路径 $NAS_LOG_DIR 不可写，请检查权限"
    exit 1
fi

REPORT_FILE="${NAS_LOG_DIR}/ClusterGate_check_${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/ClusterGate_check_${TIMESTAMP}.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# ---------------- 节点信息 ----------------
log "🔹 获取节点信息..."
NODES=$(kubectl get nodes -o wide --no-headers 2>/dev/null || echo "")
if [ -z "$NODES" ]; then
    log "${RED}❌ 无法获取节点信息${NC}"
else
    while read -r line; do
        NAME=$(echo $line | awk '{print $1}')
        STATUS=$(echo $line | awk '{print $2}')
        IP=$(echo $line | awk '{print $6}')
        log "节点: $NAME | IP: $IP | Ready状态: $STATUS"
    done <<< "$NODES"
fi

# ---------------- 本机端口检测 ----------------
PORTS=(6443 10000 10002 8080 443)
log "🔹 检查本机端口..."
PORT_HTML=""
for PORT in "${PORTS[@]}"; do
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 localhost $PORT &>/dev/null; then
            STATUS="✅ 可达"
        else
            STATUS="❌ 不可达"
        fi
    else
        log "⚠️ nc 命令不存在，请先安装 netcat"
        STATUS="⚠️ 未安装 nc"
    fi
    log "端口 $PORT: $STATUS"
    PORT_HTML+="<tr><td>端口 $PORT</td><td>$STATUS</td></tr>"
done

# ---------------- HTML 报告 ----------------
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ClusterGate - 本机端口健康检测</title>
<style>
body { font-family: sans-serif; margin: 30px; background: #f0f2f5; }
h1 { color: #1a73e8; }
table { border-collapse: collapse; width: 50%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #f8f9fa; }
</style>
</head>
<body>
<h1>ClusterGate - 本机端口健康检测</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 控制中心IP: $CONTROL_IP</p>
<table>
<tr><th>端口</th><th>状态</th></tr>
$PORT_HTML
</table>
</body>
</html>
EOF

log "${GREEN}✅ 健康检测完成${NC}"
log "HTML报告: $REPORT_FILE"
log "日志文件: $LOG_FILE"
