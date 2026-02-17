#!/bin/bash
# ==============================================================================
# 🤖 AI员工 - 人工智能Agent工厂
# 企业级-边缘机器人智慧工程-智能体基础设施健康监控平台
# KubeEdge 健康检测脚本 v3 完整版
# 输出: HTML报告 + 日志
# ==============================================================================

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# NAS 挂载路径
NAS_LOG_DIR="/mnt/truenas"
mkdir -p "$NAS_LOG_DIR"

REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

# ---------------- 颜色 ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
WARN=0
FAILED=0
SECTION_HTML=""

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# ---------------- NAS检测 ----------------
NAS_STATUS="❌ 未挂载"
NAS_WRITABLE="否"
NAS_USAGE="N/A"

if [ -d "$NAS_LOG_DIR" ]; then
    NAS_STATUS="✅ 挂载成功"
    if [ -w "$NAS_LOG_DIR" ]; then
        NAS_WRITABLE="是"
    fi
    NAS_USAGE=$(df -h "$NAS_LOG_DIR" | awk 'NR==2 {print $5}')
fi

log "NAS路径: $NAS_LOG_DIR | 状态: $NAS_STATUS | 可写: $NAS_WRITABLE | 使用率: $NAS_USAGE"
SECTION_HTML+="<tr><td>$NAS_STATUS</td><td>NAS挂载</td><td>可写: $NAS_WRITABLE, 使用率: $NAS_USAGE</td><td>-</td></tr>"

# ---------------- 硬件信息 ----------------
CPU_CORES=$(nproc)
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')

log "CPU核心: $CPU_CORES | 内存: $MEM_TOTAL ($MEM_USAGE%) | 磁盘: $DISK_TOTAL ($DISK_USAGE%)"
SECTION_HTML+="<tr><td>✅</td><td>服务器硬件</td><td>CPU: $CPU_CORES 核心, 内存: $MEM_TOTAL ($MEM_USAGE%), 磁盘: $DISK_TOTAL ($DISK_USAGE%)</td><td>-</td></tr>"

# ---------------- Kubernetes 版本 ----------------
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "未知")
log "Kubernetes版本: $K8S_VERSION"
SECTION_HTML+="<tr><td>✅</td><td>Kubernetes版本</td><td>$K8S_VERSION</td><td>-</td></tr>"

# ---------------- 节点状态 ----------------
CONTROL_NODES_HTML=""
EDGE_NODES_HTML=""

if kubectl get nodes --no-headers &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')

        # 节点类型判断
        if [[ "$NODE_NAME" =~ master ]]; then
            NODE_TYPE="控制中心"
            CONTROL_NODES_HTML+="<tr><td>✅</td><td>$NODE_NAME</td><td>$NODE_STATUS</td><td>角色: $NODE_ROLE</td></tr>"
        else
            NODE_TYPE="边缘节点"
            EDGE_NODES_HTML+="<tr><td>✅</td><td>$NODE_NAME</td><td>$NODE_STATUS</td><td>角色: $NODE_ROLE</td></tr>"
        fi

        # 节点软件类型（SSH检测，可能会阻塞）
        if ssh "$NODE_NAME" 'command -v k3s' &>/dev/null; then
            NODE_SOFTWARE="k3s"
        elif ssh "$NODE_NAME" 'command -v kubelet' &>/dev/null; then
            NODE_SOFTWARE="k8s"
        else
            NODE_SOFTWARE="edge"
        fi

        SECTION_HTML+="<tr><td>✅</td><td>$NODE_NAME ($NODE_TYPE)</td><td>$NODE_STATUS</td><td>软件类型: $NODE_SOFTWARE</td></tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "${RED}❌ 无法获取节点信息${NC}"
fi

# ---------------- 核心端口检测 ----------------
for PORT in 6443 10000 10002; do
    if nc -zv localhost $PORT &>/dev/null; then
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>-</td></tr>"
    else
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>不可达</td><td>检查服务</td></tr>"
    fi
done

# ---------------- HTML 报告 ----------------
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>🤖 AI员工 - 人工智能Agent工厂</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; background: #f0f2f5; }
.card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
h1 { color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 10px; }
h2 { color: #333; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
th { background: #f8f9fa; font-weight: bold; }
.canvas-container { width:100px; height:100px; display:inline-block; }
</style>
</head>
<body>
<div class="card">
<h1>🤖 AI员工 - 人工智能Agent工厂</h1>
<h2>企业级-边缘机器人智慧工程-智能体基础设施健康监控平台</h2>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 控制中心: $CONTROL_IP</p>
<p>健康评分: $HEALTH_SCORE%</p>
<div class="canvas-container">
<canvas id="healthChart" width="100" height="100"></canvas>
</div>

<table>
<tr><th>状态</th><th>检测项</th><th>详情</th><th>备注</th></tr>
$SECTION_HTML
</table>

<script>
const ctx = document.getElementById('healthChart').getContext('2d');
const chart = new Chart(ctx, {
    type: 'doughnut',
    data: {
        labels: ['通过', '警告', '失败'],
        datasets: [{
            data: [$PASSED, $WARN, $FAILED],
            backgroundColor: ['#28a745','#ffc107','#dc3545'],
            borderWidth: 1
        }]
    },
    options: {
        responsive: false,
        plugins: {
            legend: { display: true, position: 'bottom' }
        }
    }
});
</script>
</div>
</body>
</html>
EOF

log "${GREEN}✅ KubeEdge 健康检测完成${NC}"
log "报告: $REPORT_FILE"
log "日志: $LOG_FILE"
