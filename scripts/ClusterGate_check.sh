#!/bin/bash
# =========================================================
# 🤖 企业级节点 & 本机端口健康监控
# 输出: HTML 报告 + 日志
# =========================================================
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/ClusterGate_check_${TIMESTAMP}.log"
REPORT_FILE="/tmp/ClusterGate_check_${TIMESTAMP}.html"

PORTS=(6443 10000 10002 8080 443)
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ---------------- 安装 nc ----------------
if ! command -v nc >/dev/null 2>&1; then
    log "${YELLOW}⚠️ nc 未安装，正在安装...${NC}"
    sudo apt update && sudo apt install -y netcat
fi

# ---------------- 节点状态 ----------------
log "🔹 获取节点信息..."
SECTION_HTML=""
for node in $(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || echo ""); do
    STATUS=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    IP=$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Unknown")
    SECTION_HTML+="<tr><td>$node</td><td>$IP</td><td>$STATUS</td></tr>"
    log "节点: $node | IP: $IP | Ready状态: $STATUS"
done

# ---------------- 本机端口 ----------------
log "🔹 检查本机端口..."
PORT_HTML=""
for PORT in "${PORTS[@]}"; do
    if nc -z -w 2 localhost "$PORT" &>/dev/null; then
        PORT_HTML+="<tr><td>$PORT</td><td>✅ 可达</td></tr>"
        log "端口 $PORT: ✅ 可达"
    else
        PORT_HTML+="<tr><td>$PORT</td><td>❌ 不可达</td></tr>"
        log "端口 $PORT: ❌ 不可达"
    fi
done

# ---------------- HTML报告 ----------------
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>🤖 企业级节点 & 本机端口健康监控</title>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; margin: 30px; }
.card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
h1 { color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 10px; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
th { background: #f8f9fa; font-weight: bold; }
</style>
</head>
<body>
<div class="card">
<h1>🤖 企业级节点 & 本机端口健康监控</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>

<h2>节点状态</h2>
<table>
<tr><th>节点名</th><th>IP地址</th><th>Ready状态</th></tr>
$SECTION_HTML
</table>

<h2>本机端口检查</h2>
<table>
<tr><th>端口</th><th>状态</th></tr>
$PORT_HTML
</table>
</div>
</body>
</html>
EOF

log "${GREEN}✅ 健康检测完成${NC}"
log "HTML报告: $REPORT_FILE"
log "日志文件: $LOG_FILE"
