#!/bin/bash
# ====================================================================
# 🤖 AI员工 - 企业级 K8s & ArgoCD 端口连通性检测
# 输出: HTML报告 + 日志
# ====================================================================

set -euo pipefail

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_LOG_DIR="/mnt/truenas"
mkdir -p "$NAS_LOG_DIR"
REPORT_FILE="${NAS_LOG_DIR}/kubeedge-port-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-port-check-${TIMESTAMP}.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

PORTS=(6443 10000 10002 8080 443)

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ---------------- 安装 nc ----------------
if ! command -v nc &>/dev/null; then
    log "${YELLOW}⚠ nc (netcat) 未安装，尝试自动安装...${NC}"
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y netcat
    elif command -v yum &>/dev/null; then
        sudo yum install -y nc
    else
        log "${RED}❌ 无法自动安装 nc，请手动安装${NC}"
        exit 1
    fi
fi

# ---------------- 获取节点信息 ----------------
log "🔹 获取节点信息..."
NODES=$(kubectl get nodes --no-headers --request-timeout=5s | awk '{print $1,$2}')

SECTION_HTML=""
for node_info in $NODES; do
    NODE_NAME=$(echo $node_info | awk '{print $1}')
    NODE_STATUS=$(echo $node_info | awk '{print $2}')
    NODE_IP=$(kubectl get node $NODE_NAME -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    NODE_TYPE=$( [[ "$NODE_NAME" =~ master ]] && echo "控制中心" || echo "边缘节点" )

    PORT_STATUS=""
    for PORT in "${PORTS[@]}"; do
        if nc -z -w 2 $NODE_IP $PORT &>/dev/null; then
            PORT_STATUS+="$PORT:✅ "
        else
            PORT_STATUS+="$PORT:❌ "
        fi
    done

    # ICMP 检测
    if ping -c 1 -W 1 $NODE_IP &>/dev/null; then
        PING_STATUS="✅"
    else
        PING_STATUS="❌"
    fi

    SECTION_HTML+="<tr><td>$NODE_NAME ($NODE_TYPE)</td><td>$NODE_IP</td><td>$NODE_STATUS</td><td>$PORT_STATUS</td><td>$PING_STATUS</td></tr>"
    log "节点: $NODE_NAME | IP: $NODE_IP | 状态: $NODE_STATUS | TCP端口: $PORT_STATUS | ICMP: $PING_STATUS"
done

# ---------------- HTML 报告 ----------------
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>企业级端口连通性检测</title>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; background: #f0f2f5; }
.card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
h1 { color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 10px; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
th { background: #f8f9fa; font-weight: bold; }
</style>
</head>
<body>
<div class="card">
<h1>🤖 企业级 K8s & ArgoCD 端口连通性检测</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
<table>
<tr><th>节点</th><th>IP 地址</th><th>状态</th><th>TCP端口状态</th><th>ICMP</th></tr>
$SECTION_HTML
</table>
</div>
</body>
</html>
EOF

log "${GREEN}✅ 检测完成，报告: $REPORT_FILE${NC}"
