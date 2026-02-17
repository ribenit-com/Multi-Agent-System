#!/bin/bash
# ============================================
# KubeEdge 集群健康检测脚本 (安全版)
# 版本: 2.1.0
# 输出: HTML报告 + 日志 (保存到NAS挂载路径)
# ============================================

# ================= 配置 =================
CONTROL_IP=$(hostname -I | awk '{print $1}')
NETWORK_PREFIX="192.168.1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 你的NAS挂载路径（确保已挂载且有写权限）
NAS_LOG_DIR="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
mkdir -p "$NAS_LOG_DIR"

REPORT_FILE="${NAS_LOG_DIR}/kubeedge-health-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-health-check-${TIMESTAMP}.log"

[ -f "$REPORT_FILE" ] && rm -f "$REPORT_FILE"
[ -f "$LOG_FILE" ] && rm -f "$LOG_FILE"

# ================= 控制台颜色 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ================= 初始化计数 =================
TOTAL_CHECKS=0; PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""; ERROR_DETAILS=""

# ================= 日志函数 =================
log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ================= 开始检测 =================
log "${BLUE}════════════════ KubeEdge 健康检测开始 (${TIMESTAMP}) ════════════════${NC}"
log ""

# ================= 1. 网络健康检查 =================
log "${YELLOW}[1/5] 网络健康检查${NC}"
INTERFACES=$(ip -br addr | grep -v "lo" | wc -l || echo 0)
if [ "$INTERFACES" -gt 0 ]; then
    log "  ${GREEN}✓${NC} 网络接口正常 ($INTERFACES 个活动接口)"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>控制中心网络接口</td><td>正常</td><td>$INTERFACES 个接口</td></tr>"
else
    log "  ${RED}✗${NC} 未找到活动网络接口"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>控制中心网络接口</td><td>失败</td><td>未找到活动接口</td></tr>"
fi

log "  扫描网络 ${NETWORK_PREFIX}.0/24..."
if ! command -v nmap &>/dev/null; then
    log "  ${YELLOW}⚠${NC} nmap 未安装，无法扫描网络节点"
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>网络节点扫描</td><td>未执行</td><td>请安装 nmap</td></tr>"
else
    NODE_IPS=$(nmap -sn ${NETWORK_PREFIX}.0/24 2>/dev/null | grep "Nmap scan" | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "")
    NODES_FOUND=$(echo "$NODE_IPS" | wc -w)
    if [ "$NODES_FOUND" -gt 1 ]; then
        log "  ${GREEN}✓${NC} 发现 $((NODES_FOUND-1)) 个边缘节点"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>网络节点扫描</td><td>发现 $((NODES_FOUND-1)) 个节点</td><td>-</td></tr>"
    else
        log "  ${YELLOW}⚠${NC} 未发现边缘节点"
        WARN=$((WARN+1))
        SECTION_HTML+="<tr><td>⚠️</td><td>网络节点扫描</td><td>未发现节点</td><td>请确认边缘节点已上线</td></tr>"
    fi
fi

for PORT in 6443 10250; do
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 可达"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>Kube$PORT</td><td>端口可达</td><td>-</td></tr>"
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>❌</td><td>Kube$PORT</td><td>端口不可达</td><td>检查服务</td></tr>"
    fi
done
log ""

# ================= 2. 硬件健康检查 =================
log "${YELLOW}[2/5] 硬件健康检查${NC}"
CPU_CORES=$(nproc || echo 0)
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}' || echo "N/A")
log "  CPU: $CPU_CORES 核心, 负载:$CPU_LOAD"
[ "$CPU_CORES" -gt 0 ] && PASSED=$((PASSED+1))
SECTION_HTML+="<tr><td>✅</td><td>CPU</td><td>$CPU_CORES 核心</td><td>负载:$CPU_LOAD</td></tr>"

MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}' || echo "N/A")
MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}' || echo "N/A")
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}' || echo "0")
log "  内存总量: $MEM_TOTAL, 可用: $MEM_AVAIL, 使用率: ${MEM_USAGE}%"
if (( $(echo "$MEM_USAGE < 80" | bc -l) )); then
    PASSED=$((PASSED+1))
elif (( $(echo "$MEM_USAGE < 90" | bc -l) )); then
    WARN=$((WARN+1))
else
    FAILED=$((FAILED+1))
fi

DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}' || echo "N/A")
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}' || echo "N/A")
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
log "  磁盘总量: $DISK_TOTAL, 可用: $DISK_AVAIL, 使用率: ${DISK_USAGE}%"
if [ "$DISK_USAGE" -lt 80 ]; then
    PASSED=$((PASSED+1))
elif [ "$DISK_USAGE" -lt 90 ]; then
    WARN=$((WARN+1))
else
    FAILED=$((FAILED+1))
fi
log ""

# ================= 3. 配置健康检查 =================
log "${YELLOW}[3/5] 配置健康检查${NC}"
if [ -f ~/.kube/config ]; then
    log "  ${GREEN}✓${NC} kubeconfig 文件存在"
    PASSED=$((PASSED+1))
else
    log "  ${RED}✗${NC} kubeconfig 文件不存在"
    FAILED=$((FAILED+1))
fi

if [ -n "${KUBECONFIG:-}" ]; then
    log "  ${GREEN}✓${NC} KUBECONFIG 已设置"
    PASSED=$((PASSED+1))
else
    log "  ${YELLOW}⚠${NC} KUBECONFIG 未设置"
    WARN=$((WARN+1))
fi
TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}' || echo "N/A")
log "  系统时区: $TIMEZONE"
PASSED=$((PASSED+1))
log ""

# ================= 4. Kubernetes服务健康检查 =================
log "${YELLOW}[4/5] Kubernetes服务健康检查${NC}"
if kubectl get nodes &>/dev/null; then
    log "  ${GREEN}✓${NC} kubectl 能连接集群"
    PASSED=$((PASSED+1))
else
    log "  ${RED}✗${NC} kubectl 无法连接集群"
    FAILED=$((FAILED+1))
fi

NODES=$(kubectl get nodes -o name 2>/dev/null || echo "")
NODE_COUNT=$(echo "$NODES" | wc -w)
READY_NODES=$(kubectl get nodes 2>/dev/null | grep "Ready" | wc -l || echo 0)
log "  总节点: $NODE_COUNT, 就绪节点: $READY_NODES"
if [ "$NODE_COUNT" -gt 0 ] && [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    PASSED=$((PASSED+1))
elif [ "$NODE_COUNT" -gt 0 ]; then
    FAILED=$((FAILED+1))
fi
log ""

# ================= 5. 边缘节点检查 =================
log "${YELLOW}[5/5] 边缘节点握手状态检查${NC}"
EDGE_NODES=$(kubectl get nodes -o name 2>/dev/null | grep -v "$(hostname)" | sed 's|node/||' || echo "")
EDGE_NODE_COUNT=$(echo "$EDGE_NODES" | wc -w)
if [ "$EDGE_NODE_COUNT" -gt 0 ]; then
    log "  发现 $EDGE_NODE_COUNT 个边缘节点"
    PASSED=$((PASSED+1))
    for NODE in $EDGE_NODES; do
        NODE_STATUS=$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' || echo "Unknown")
        NODE_IP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' || echo "-")
        if [ "$NODE_STATUS" == "True" ]; then
            log "  ${GREEN}✓${NC} $NODE ($NODE_IP) Ready"
            PASSED=$((PASSED+1))
        else
            log "  ${RED}✗${NC} $NODE ($NODE_IP) NotReady"
            FAILED=$((FAILED+1))
        fi
        if [ -n "$NODE_IP" ]; then
            if ping -c 1 -W 2 $NODE_IP &>/dev/null; then
                log "    - 网络可达"
            else
                log "    - 网络不可达"
            fi
        fi
    done
else
    log "  ${YELLOW}⚠${NC} 未发现边缘节点"
    WARN=$((WARN+1))
fi
log ""

# ================= 生成报告 =================
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>KubeEdge 健康检测报告</title></head><body>
<h1>KubeEdge 健康检测报告</h1>
<p>生成时间: $(date) | 控制中心: $CONTROL_IP</p>
<p>总检查: $TOTAL_CHECKS, 通过: $PASSED, 警告: $WARN, 失败: $FAILED, 健康评分: $HEALTH_SCORE%</p>
<table border="1" cellpadding="5" cellspacing="0">
<tr><th>状态</th><th>检查项</th><th>结果</th><th>备注</th></tr>
$SECTION_HTML
</table>
</body></html>
EOF

log ""
log "✅ 报告生成: $REPORT_FILE"
log "✅ 日志文件: $LOG_FILE"
log "提示: 使用浏览器打开报告: file://$REPORT_FILE"

# ================= 返回状态码 =================
if [ $FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
