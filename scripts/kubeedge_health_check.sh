#!/bin/bash
# ============================================
# KubeEdge 集群全面健康检测脚本
# 版本: 2.0.0
# 执行位置: 控制中心 (192.168.1.10)
# 输出: HTML格式健康报告 + 日志，保存到NAS
# ============================================

set -euo pipefail

# ================= 配置 =================
CONTROL_IP="192.168.1.10"
NETWORK_PREFIX="192.168.1"

# NAS路径
NAS_PATH="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
if [ ! -d "$NAS_PATH" ]; then
    echo -e "\033[0;31m❌ NAS路径 $NAS_PATH 不存在或未挂载，请先挂载NAS\033[0m"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$NAS_PATH/kubeedge-health-report-${TIMESTAMP}.html"
LOG_FILE="$NAS_PATH/kubeedge-health-check-${TIMESTAMP}.log"

# 删除同名旧文件（防止重复执行冲突）
[ -f "$REPORT_FILE" ] && rm -f "$REPORT_FILE"
[ -f "$LOG_FILE" ] && rm -f "$LOG_FILE"

# ================= 控制台颜色 =================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ================= 初始化计数 =================
TOTAL_CHECKS=0
PASSED=0
WARN=0
FAILED=0

SECTION_HTML=""
ERROR_DETAILS=""

# ================= 日志函数 =================
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# ================= 开始检测 =================
log "${BLUE}════════════════════════════════════════════════════════════${NC}"
log "${BLUE}      KubeEdge 集群全面健康检测 - $(date)${NC}"
log "${BLUE}════════════════════════════════════════════════════════════${NC}"
log ""

# ================= 1. 网络健康检查 =================
log "${YELLOW}[1/5] 网络健康检查${NC}"

# 1.1 网络接口
log "  检查控制中心网络接口..."
INTERFACES=$(ip -br addr | grep -v "lo" | wc -l)
if [ $INTERFACES -gt 0 ]; then
    log "  ${GREEN}✓${NC} 网络接口正常 (找到 $INTERFACES 个活动接口)"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>控制中心网络接口</td><td>正常 ($INTERFACES 个接口)</td><td>-</td></tr>"
else
    log "  ${RED}✗${NC} 未找到活动网络接口"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>控制中心网络接口</td><td>失败</td><td>未找到活动网络接口</td></tr>"
fi

# 1.2 扫描网络节点
log "  扫描网络 ${NETWORK_PREFIX}.0/24..."
if ! command -v nmap &>/dev/null; then
    log "  ${YELLOW}⚠${NC} nmap 未安装，无法扫描网络节点"
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>网络节点扫描</td><td>未执行</td><td>请安装nmap</td></tr>"
else
    NODE_IPS=$(nmap -sn ${NETWORK_PREFIX}.0/24 2>/dev/null | grep "Nmap scan" | grep -oP '\d+\.\d+\.\d+\.\d+' || echo "")
    NODES_FOUND=$(echo "$NODE_IPS" | wc -w)
    if [ $NODES_FOUND -gt 1 ]; then
        log "  ${GREEN}✓${NC} 发现 $((NODES_FOUND-1)) 个边缘节点"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>网络节点扫描</td><td>发现 $((NODES_FOUND-1)) 个节点</td><td>-</td></tr>"
        for IP in $NODE_IPS; do
            [ "$IP" != "$CONTROL_IP" ] && log "    - 发现边缘节点: $IP"
        done
    else
        log "  ${YELLOW}⚠${NC} 未发现边缘节点"
        WARN=$((WARN+1))
        SECTION_HTML+="<tr><td>⚠️</td><td>网络节点扫描</td><td>未发现节点</td><td>请确认边缘节点已上线</td></tr>"
    fi
fi

# 1.3 核心端口
for PORT in 6443 10250; do
    SERVICE_NAME="Kube${PORT}"
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 可达"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>$SERVICE_NAME</td><td>端口可达</td><td>-</td></tr>"
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>❌</td><td>$SERVICE_NAME</td><td>端口不可达</td><td>检查服务状态</td></tr>"
    fi
done
log ""

# ================= 2. 硬件健康检查 =================
log "${YELLOW}[2/5] 硬件健康检查${NC}"

# CPU
CPU_CORES=$(nproc)
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}')
log "  CPU: $CPU_CORES 核心, 负载:$CPU_LOAD"
[ $CPU_CORES -gt 0 ] && PASSED=$((PASSED+1))
SECTION_HTML+="<tr><td>✅</td><td>CPU</td><td>${CPU_CORES} 核心</td><td>负载: $CPU_LOAD</td></tr>"

# 内存
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}')
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
log "  内存总量: $MEM_TOTAL, 可用: $MEM_AVAIL, 使用率: ${MEM_USAGE}%"
if (( $(echo "$MEM_USAGE < 80" | bc -l) )); then
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>内存</td><td>$MEM_TOTAL</td><td>使用率: ${MEM_USAGE}%</td></tr>"
elif (( $(echo "$MEM_USAGE < 90" | bc -l) )); then
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>内存</td><td>$MEM_TOTAL</td><td>使用率: ${MEM_USAGE}% (接近警戒)</td></tr>"
else
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>内存</td><td>$MEM_TOTAL</td><td>使用率: ${MEM_USAGE}% (超过警戒)</td></tr>"
fi

# 磁盘
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
log "  磁盘总量: $DISK_TOTAL, 可用: $DISK_AVAIL, 使用率: ${DISK_USAGE}%"
if [ $DISK_USAGE -lt 80 ]; then
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>磁盘</td><td>$DISK_TOTAL</td><td>使用率: $DISK_USAGE%</td></tr>"
elif [ $DISK_USAGE -lt 90 ]; then
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>磁盘</td><td>$DISK_TOTAL</td><td>使用率: $DISK_USAGE% (接近警戒)</td></tr>"
else
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>磁盘</td><td>$DISK_TOTAL</td><td>使用率: $DISK_USAGE% (超过警戒)</td></tr>"
fi
log ""

# ================= 3. 配置健康检查 =================
log "${YELLOW}[3/5] 配置健康检查${NC}"
if [ -f ~/.kube/config ]; then
    log "  ${GREEN}✓${NC} kubeconfig 文件存在"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>kubeconfig</td><td>文件存在</td><td>~/.kube/config</td></tr>"
else
    log "  ${RED}✗${NC} kubeconfig 文件不存在"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>kubeconfig</td><td>不存在</td><td>需配置kubectl</td></tr>"
fi

if [ -n "${KUBECONFIG:-}" ]; then
    log "  ${GREEN}✓${NC} KUBECONFIG 环境变量已设置"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>环境变量</td><td>KUBECONFIG已设置</td><td>$KUBECONFIG</td></tr>"
else
    log "  ${YELLOW}⚠${NC} KUBECONFIG 未设置（使用默认配置）"
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>环境变量</td><td>未设置</td><td>使用默认 ~/.kube/config</td></tr>"
fi

TIMEZONE=$(timedatectl | grep "Time zone" | awk '{print $3}')
log "  系统时区: $TIMEZONE"
PASSED=$((PASSED+1))
SECTION_HTML+="<tr><td>✅</td><td>系统时区</td><td>$TIMEZONE</td><td>-</td></tr>"
log ""

# ================= 4. Kubernetes服务健康检查 =================
log "${YELLOW}[4/5] Kubernetes服务健康检查${NC}"
if kubectl get nodes &>/dev/null; then
    log "  ${GREEN}✓${NC} kubectl 能连接集群"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>kubectl连接</td><td>正常</td><td>-</td></tr>"
else
    log "  ${RED}✗${NC} kubectl 无法连接集群"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>kubectl连接</td><td>失败</td><td>检查kube-apiserver</td></tr>"
fi

# 节点状态
NODES=$(kubectl get nodes -o json 2>/dev/null || echo "{}")
NODE_COUNT=$(echo "$NODES" | jq '.items|length' 2>/dev/null || echo "0")
READY_NODES=$(echo "$NODES" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
log "  总节点: $NODE_COUNT, 就绪节点: $READY_NODES"
if [ "$NODE_COUNT" -gt 0 ] && [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>集群节点</td><td>$READY_NODES/$NODE_COUNT 就绪</td><td>-</td></tr>"
elif [ "$READY_NODES" -lt "$NODE_COUNT" ]; then
    FAILED=$((FAILED+1))
    NOT_READY=$((NODE_COUNT-READY_NODES))
    SECTION_HTML+="<tr><td>❌</td><td>集群节点</td><td>$READY_NODES/$NODE_COUNT 就绪</td><td>$NOT_READY 个未就绪</td></tr>"
    NOT_READY_NODES=$(echo "$NODES" | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | .metadata.name')
    for NODE in $NOT_READY_NODES; do
        ERROR_DETAILS+="节点 $NODE 未就绪<br>"
    done
fi
log ""

# ================= 5. 边缘节点握手状态 =================
log "${YELLOW}[5/5] 边缘节点握手状态检查${NC}"
EDGE_NODES=$(kubectl get nodes -o name 2>/dev/null | grep -v "$(hostname)" | sed 's|node/||')
EDGE_NODE_COUNT=$(echo "$EDGE_NODES" | wc -w)
if [ $EDGE_NODE_COUNT -gt 0 ]; then
    log "  发现 $EDGE_NODE_COUNT 个边缘节点"
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>边缘节点发现</td><td>$EDGE_NODE_COUNT 个</td><td>-</td></tr>"
    for NODE in $EDGE_NODES; do
        NODE_STATUS=$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        NODE_IP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
        if [ "$NODE_STATUS" == "True" ]; then
            log "  ${GREEN}✓${NC} $NODE ($NODE_IP) Ready"
            PASSED=$((PASSED+1))
            SECTION_HTML+="<tr><td>✅</td><td>$NODE</td><td>Ready</td><td>IP: $NODE_IP</td></tr>"
        else
            log "  ${RED}✗${NC} $NODE ($NODE_IP) NotReady"
            FAILED=$((FAILED+1))
            SECTION_HTML+="<tr><td>❌</td><td>$NODE</td><td>NotReady</td><td>IP: $NODE_IP</td></tr>"
            ERROR_DETAILS+="边缘节点 $NODE 未就绪<br>"
        fi
        # ping测试
        if [ -n "$NODE_IP" ]; then
            if ping -c 1 -W 2 $NODE_IP &>/dev/null; then
                log "    - 网络可达"
            else
                log "    - 网络不可达"
                ERROR_DETAILS+="节点 $NODE IP $NODE_IP 网络不可达<br>"
            fi
        fi
    done
else
    log "  ${YELLOW}⚠${NC} 未发现边缘节点"
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>边缘节点</td><td>未发现</td><td>请确认边缘节点已加入集群</td></tr>"
fi
log ""

# ================= 生成报告 =================
TOTAL_CHECKS=$((PASSED + WARN + FAILED))
HEALTH_SCORE=$((PASSED*100/TOTAL_CHECKS))

# HTML报告
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>KubeEdge 集群健康报告</title></head>
<body>
<h1>KubeEdge 集群健康检测报告</h1>
<p>生成时间: $(date) | 控制中心: $CONTROL_IP</p>
<p>总检查: $TOTAL_CHECKS, 通过: $PASSED, 警告: $WARN, 失败: $FAILED, 健康评分: $HEALTH_SCORE%</p>
<table border="1" cellpadding="5">
<tr><th>状态</th><th>检查项</th><th>结果</th><th>备注</th></tr>
$SECTION_HTML
</table>
EOF

# 错误详情
if [ -n "$ERROR_DETAILS" ]; then
cat >> "$REPORT_FILE" <<EOF
<div style="color:red;">
<h2>错误详情</h2>
<p>$ERROR_DETAILS</p>
</div>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</body></html>
EOF

# ================= 输出控制台 =================
log ""
log "${BLUE}══════════ 检查汇总 ══════════${NC}"
log "总检查项: $TOTAL_CHECKS, ${GREEN}通过: $PASSED${NC}, ${YELLOW}警告: $WARN${NC}, ${RED}失败: $FAILED${NC}"
log "${GREEN}✅ 报告生成: $REPORT_FILE${NC}"
log "${GREEN}✅ 日志文件: $LOG_FILE${NC}"

# 自动打开（桌面环境）
if [ -n "${DISPLAY:-}" ] && command -v xdg-open &>/dev/null; then
    xdg-open "$REPORT_FILE"
else
    log "提示: 使用浏览器打开报告: file://$REPORT_FILE"
fi

# ================= 返回状态码 =================
if [ $FAILED -gt 0 ]; then
    exit 1
else
    exit 0
fi
