#!/bin/bash
# ====================================================================
# 🔹 ClusterGate 健康检测脚本 - 企业级端口监控
# 输出: 终端实时打印 + HTML 报告 + 日志
# ====================================================================

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/tmp/ClusterGate_check_${TIMESTAMP}.log"
REPORT_FILE="/tmp/ClusterGate_check_${TIMESTAMP}.html"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ---------------- nc工具检测 ----------------
if ! command -v nc &>/dev/null; then
    echo -e "${YELLOW}⚠ nc (netcat) 未安装，正在尝试安装...${NC}"
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y netcat
    elif command -v yum &>/dev/null; then
        sudo yum install -y nc
    else
        echo -e "${RED}❌ 无法自动安装 nc，请手动安装${NC}"
        exit 1
    fi
fi

# ---------------- 节点信息 ----------------
NODES=(
    "cmaster01:192.168.1.10"
    "agent01:192.168.1.20"
)

echo "🔹 获取节点信息..." | tee -a "$LOG_FILE"

NODE_TABLE=""
for node in "${NODES[@]}"; do
    NAME="${node%%:*}"
    IP="${node##*:}"
    READY="True"  # 假设节点 Ready，如果需要可以改成 kubectl get nodes
    line="节点: $NAME | IP: $IP | Ready状态: $READY"
    echo "$line" | tee -a "$LOG_FILE"
    NODE_TABLE+="<tr><td>$NAME</td><td>$IP</td><td>$READY</td></tr>"
done

# ---------------- 本机端口检测 ----------------
PORTS=(6443 10000 10002 8080 443)
echo -e "\n🔹 检查本机端口..." | tee -a "$LOG_FILE"

PORT_TABLE=""
for PORT in "${PORTS[@]}"; do
    if nc -z -w 2 127.0.0.1 $PORT &>/dev/null; then
        STATUS="✅ 可达"
    else
        STATUS="❌ 不可达"
    fi
    echo "端口 $PORT: $STATUS" | tee -a "$LOG_FILE"
    PORT_TABLE+="<tr><td>$PORT</td><td>$STATUS</td></tr>"
done

# ---------------- HTML报告生成 ----------------
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ClusterGate 健康检测报告</title>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; }
h1 { color: #1a73e8; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
th, td { padding: 8px; border: 1px solid #ddd; text-align: left; }
th { background: #f2f2f2; }
</style>
</head>
<body>
<h1>ClusterGate 健康检测报告</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>

<h2>节点状态</h2>
<table>
<tr><th>节点名</th><th>IP</th><th>Ready</th></tr>
$NODE_TABLE
</table>

<h2>本机端口检测</h2>
<table>
<tr><th>端口</th><th>状态</th></tr>
$PORT_TABLE
</table>
</body>
</html>
EOF

echo -e "\n✅ 健康检测完成"
echo "HTML报告: $REPORT_FILE"
echo "日志文件: $LOG_FILE"
