#!/bin/bash
# ==============================================================================
# 企业级 KubeEdge 健康检查 v3
# 集成: 节点状态 + K8s版本 + NAS检测 + 系统硬件信息 + 饼图
# ==============================================================================
export KUBECONFIG=/home/zdl/.kube/config

# ================= 配置 =================
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_PATH="/mnt/truenas"
REPORT_FILE="${NAS_PATH}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_PATH}/kubeedge-check-${TIMESTAMP}.log"

# ================= 颜色 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""; SYS_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ================= 检查 NAS =================
log "检测 NAS 挂载: $NAS_PATH"
if [ ! -d "$NAS_PATH" ] || [ ! -w "$NAS_PATH" ]; then
    log "${RED}❌ NAS 路径未挂载或不可写: $NAS_PATH${NC}"
    exit 1
else
    log "${GREEN}✅ NAS 可用${NC}"
fi

# ================= 系统硬件信息 =================
CPU_CORES=$(nproc)
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}')
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_USED=$(free -h | awk '/^Mem:/{print $3}')
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

SYS_HTML+="<tr><td>CPU 核心</td><td>$CPU_CORES</td></tr>"
SYS_HTML+="<tr><td>CPU 负载</td><td>$CPU_LOAD</td></tr>"
SYS_HTML+="<tr><td>内存总量</td><td>$MEM_TOTAL</td></tr>"
SYS_HTML+="<tr><td>内存使用</td><td>$MEM_USED ($MEM_USAGE%)</td></tr>"
SYS_HTML+="<tr><td>磁盘总量</td><td>$DISK_TOTAL</td></tr>"
SYS_HTML+="<tr><td>磁盘使用</td><td>$DISK_USED ($DISK_USAGE%)</td></tr>"

# ================= 核心端口检测 =================
log "检查核心端口: 6443,10250,10000,10002"
for PORT in 6443 10250 10000 10002; do
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓ 端口 $PORT 正常${NC}"; PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>-</td><td>-</td></tr>"
    else
        log "  ${RED}✗ 端口 $PORT 不可达${NC}"; FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>不可达</td><td>-</td><td>-</td></tr>"
    fi
done

# ================= K8s节点状态 =================
log "检测 K8s 节点状态"
if kubectl get nodes &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')
        NODE_VERSION=$(echo $line | awk '{print $5}')

        if [[ "$NODE_STATUS" == "Ready" ]]; then
            STATUS_ICON="✅"; PASSED=$((PASSED+1))
            log "  ${GREEN}✓ 节点 $NODE_NAME [$NODE_VERSION] ($NODE_ROLE)${NC}"
        else
            STATUS_ICON="❌"; FAILED=$((FAILED+1))
            log "  ${RED}✗ 节点 $NODE_NAME [$NODE_VERSION] ($NODE_ROLE)${NC}"
        fi
        SECTION_HTML+="<tr><td>$STATUS_ICON</td><td>节点: $NODE_NAME</td><td>$NODE_STATUS</td><td>$NODE_ROLE</td><td>$NODE_VERSION</td></tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "${RED}❌ 无法获取 K8s 节点信息${NC}"; FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>K8s 集群连接</td><td>失败</td><td>-</td><td>-</td></tr>"
fi

# ================= 生成 HTML =================
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>AI员工-人工智能Agent工厂</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background:#f0f2f5; }
h1 { color:#1a73e8; }
h2 { color:#555; }
.card { background:white; padding:20px; border-radius:8px; margin-bottom:20px; }
table { width:100%; border-collapse: collapse; margin-top:10px; }
th, td { padding:8px; border:1px solid #ccc; text-align:left; }
th { background:#f8f9fa; }
.pie { width:100px; height:100px; }
</style>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
<h1>🤖 AI员工 - 人工智能Agent工厂</h1>
<h2>企业级-边缘机器人智慧工程-智能体基础设施健康监控平台</h2>

<div class="card">
<h3>总体健康评分: $HEALTH_SCORE%</h3>
<canvas id="pieChart" class="pie"></canvas>
<p>通过: $PASSED | 警告: $WARN | 失败: $FAILED</p>
</div>

<div class="card">
<h3>核心节点 & K8s状态</h3>
<table>
<tr><th>状态</th><th>检测项</th><th>节点状态</th><th>角色</th><th>K8s版本</th></tr>
$SECTION_HTML
</table>
</div>

<div class="card">
<h3>服务器基本信息</h3>
<table>
<tr><th>项目</th><th>信息</th></tr>
$SYS_HTML
<tr><td>NAS挂载</td><td>$NAS_PATH</td></tr>
</table>
</div>

<script>
const ctx = document.getElementById('pieChart').getContext('2d');
const myPie = new Chart(ctx, {
    type: 'doughnut',
    data: {
        labels: ['通过','警告','失败'],
        datasets:[{
            data: [$PASSED,$WARN,$FAILED],
            backgroundColor: ['#28a745','#ffc107','#dc3545']
        }]
    },
    options:{plugins:{legend:{position:'bottom'}},maintainAspectRatio:false}
});
</script>
</body>
</html>
EOF

log "${GREEN}✅ 报告生成完成: $REPORT_FILE${NC}"
log "  详细日志: $LOG_FILE"
