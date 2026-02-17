#!/bin/bash
# ==============================================================================
# 🤖 AI员工 - 人工智能Agent工厂
# 企业级-边缘机器人智慧工程-智能体基础设施健康监控平台
# KubeEdge 集群健康检测 v4 (企业版)
# ==============================================================================
export KUBECONFIG=/home/zdl/.kube/config

# ================= 配置 =================
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_LOG_DIR="/mnt/truenas"
REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

# ================= 颜色 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""
NODE_SUMMARY_HTML=""
NODE_TOTAL=0; CONTROL_NODES=0; WORKER_NODES=0; EDGE_NODES=0

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ================= 初始化 =================
mkdir -p "$NAS_LOG_DIR"
touch "$LOG_FILE" || { echo "无法写入日志 $LOG_FILE"; exit 1; }
log "${BLUE}════════════════ KubeEdge 健康检测开始 (${TIMESTAMP}) ════════════════${NC}"

# ================= NAS挂载检查 =================
log "${YELLOW}[1/6] NAS挂载检测...${NC}"
if [ -d "$NAS_LOG_DIR" ] && [ -w "$NAS_LOG_DIR" ]; then
    log "  ${GREEN}✓${NC} NAS 挂载正常: $NAS_LOG_DIR"
    PASSED=$((PASSED+1))
else
    log "  ${RED}✗${NC} NAS 挂载异常或无写权限: $NAS_LOG_DIR"
    FAILED=$((FAILED+1))
fi

# ================= 硬件检测 =================
log "${YELLOW}[2/6] 服务器硬件信息...${NC}"
CPU_CORES=$(nproc)
CPU_LOAD=$(uptime | awk -F'load average:' '{print $2}')
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}')
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_TOTAL=$(df / | awk 'NR==2 {print $2}')
DISK_AVAIL=$(df / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

log "  CPU: $CPU_CORES 核心, 负载:$CPU_LOAD"
log "  内存: $MEM_TOTAL, 可用:$MEM_AVAIL, 使用率:${MEM_USAGE}%"
log "  磁盘: $DISK_TOTAL, 可用:$DISK_AVAIL, 使用率:${DISK_USAGE}%"

SECTION_HTML+="<tr><td>硬件信息</td><td>CPU</td><td>$CPU_CORES 核心</td><td>负载:$CPU_LOAD</td></tr>"
SECTION_HTML+="<tr><td>硬件信息</td><td>内存</td><td>$MEM_TOTAL 可用:$MEM_AVAIL</td><td>使用率:${MEM_USAGE}%</td></tr>"
SECTION_HTML+="<tr><td>硬件信息</td><td>磁盘</td><td>$DISK_TOTAL 可用:$DISK_AVAIL</td><td>使用率:${DISK_USAGE}%</td></tr>"

# ================= 核心端口检测 =================
log "${YELLOW}[3/6] 核心端口检测...${NC}"
for PORT in 6443 10250; do
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 正常"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>端口检测</td><td>$PORT</td><td>可达</td><td>服务运行中</td></tr>"
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>端口检测</td><td>$PORT</td><td>失败</td><td>请检查相关 K8s/Edge 组件</td></tr>"
    fi
done

# ================= K8s节点检测 =================
log "${YELLOW}[4/6] Kubernetes节点信息...${NC}"
if kubectl get nodes &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/master}' 2>/dev/null)
        NODE_ROLE=${NODE_ROLE:-$(kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels.node-role}' 2>/dev/null)}
        NODE_VERSION=$(kubectl get node $NODE_NAME -o jsonpath='{.status.nodeInfo.kubeletVersion}')
        NODE_SOFTWARE="k8s"
        if kubectl get node $NODE_NAME -o jsonpath='{.status.nodeInfo.kubeProxyVersion}' 2>/dev/null | grep -q "k3s"; then
            NODE_SOFTWARE="k3s"
        fi
        if [[ $NODE_ROLE == "edge" ]]; then NODE_SOFTWARE="edge"; fi

        STATUS_ICON="❌"
        if [[ "$NODE_STATUS" == "Ready" ]]; then
            STATUS_ICON="✅"; PASSED=$((PASSED+1))
        else
            FAILED=$((FAILED+1))
        fi

        SECTION_HTML+="<tr><td>$STATUS_ICON</td><td>节点: $NODE_NAME</td><td>状态: $NODE_STATUS</td><td>角色: $NODE_ROLE | 软件: $NODE_SOFTWARE | 版本: $NODE_VERSION</td></tr>"

        NODE_TOTAL=$((NODE_TOTAL+1))
        case "$NODE_ROLE" in
            master|control-plane) CONTROL_NODES=$((CONTROL_NODES+1)) ;;
            edge) EDGE_NODES=$((EDGE_NODES+1)) ;;
            *) WORKER_NODES=$((WORKER_NODES+1)) ;;
        esac
    done < <(kubectl get nodes --no-headers)
else
    log "  ${RED}❌ 无法获取 K8s 节点信息${NC}"
    FAILED=$((FAILED+1))
fi

NODE_SUMMARY_HTML="<tr><th>类别</th><th>节点数</th></tr>
<tr><td>控制节点</td><td>$CONTROL_NODES</td></tr>
<tr><td>工作节点</td><td>$WORKER_NODES</td></tr>
<tr><td>边缘节点</td><td>$EDGE_NODES</td></tr>
<tr><td>总节点数</td><td>$NODE_TOTAL</td></tr>"

# ================= 生成饼图比例 =================
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

# ================= 生成 HTML =================
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>AI员工 - 人工智能Agent工厂健康报告</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; margin: 20px; }
.card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 6px rgba(0,0,0,0.1); margin-bottom:20px; }
h1 { color: #1a73e8; border-bottom:2px solid #1a73e8; padding-bottom:10px; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
th, td { border:1px solid #ddd; padding:8px; text-align:left; }
th { background:#f8f9fa; }
.chart-container { width:100%; height:100px; }
</style>
</head>
<body>

<div class="card">
<h1>🤖 AI员工 - 人工智能Agent工厂</h1>
<p>企业级-边缘机器人智慧工程-智能体基础设施健康监控平台</p>
<div class="chart-container">
<canvas id="healthChart" height="100"></canvas>
<script>
const ctx = document.getElementById('healthChart').getContext('2d');
const data = {
    labels: ['通过','警告','失败'],
    datasets: [{ data: [$PASSED,$WARN,$FAILED], backgroundColor:['#28a745','#ffc107','#dc3545'] }]
};
new Chart(ctx, { type:'doughnut', data:data, options:{ plugins:{ legend:{ position:'bottom' } } } });
</script>
</div>
<p>健康评分: $HEALTH_SCORE%</p>
<p>总检查项: $TOTAL_CHECKS | 通过: $PASSED | 警告: $WARN | 失败: $FAILED</p>
</div>

<div class="card">
<h2>节点总览</h2>
<table>$NODE_SUMMARY_HTML</table>
</div>

<div class="card">
<h2>节点详情</h2>
<table>$SECTION_HTML</table>
</div>

</body>
</html>
EOF

log ""
log "${GREEN}✅ 健康检测完成！${NC}"
log "  HTML报告: $REPORT_FILE"
log "  日志文件: $LOG_FILE"
