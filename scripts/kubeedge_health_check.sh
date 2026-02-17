#!/bin/bash
# ==============================================================================
# 企业级 KubeEdge 健康检测 v3
# 完整报告：节点分类、NAS检测、图表、服务器配置
# ==============================================================================
# 作者: ribenit
# 版本: 3.0
# ==============================================================================

# ================= 配置 =================
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_LOG_DIR="/mnt/truenas"   # NAS 挂载路径
REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

# ================= 初始化颜色 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# ================= 初始化计数 =================
PASSED=0; WARN=0; FAILED=0
CORE_COUNT=0; WORKER_COUNT=0; EDGE_COUNT=0; EDGE_READY=0
SECTION_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ================= 依赖检查 =================
log "${BLUE}初始化检测环境...${NC}"
if ! command -v nc &>/dev/null; then
    log "${YELLOW}未发现 netcat，尝试安装...${NC}"
    if [ "$EUID" -ne 0 ]; then
        log "${RED}安装需要 root 权限，请用 sudo 运行脚本${NC}"
        exit 1
    fi
    apt-get update && apt-get install netcat-openbsd -y
    [ $? -eq 0 ] && log "${GREEN}✓ netcat 安装成功${NC}" || { log "${RED}✗ netcat 安装失败${NC}"; exit 1; }
fi

# ================= NAS 挂载检查 =================
NAS_STATUS="未挂载或不可写"
if [ -d "$NAS_LOG_DIR" ] && [ -w "$NAS_LOG_DIR" ]; then
    NAS_STATUS="正常"
    PASSED=$((PASSED+1))
else
    log "${RED}❌ NAS 路径 $NAS_LOG_DIR 未挂载或不可写${NC}"
    exit 1
fi

# ================= 核心检测项目 =================
log "${BLUE}开始节点与端口检测...${NC}"

# --- 核心端口检测 ---
for PORT in 6443 10250 10000 10002; do
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 正常"
        PASSED=$((PASSED+1))
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
    fi
done

# --- 节点状态检测 ---
if kubectl get nodes &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')

        case $NODE_ROLE in
            control-plane) CORE_COUNT=$((CORE_COUNT+1));;
            worker) WORKER_COUNT=$((WORKER_COUNT+1));;
            edge) EDGE_COUNT=$((EDGE_COUNT+1));;
        esac

        if [[ "$NODE_STATUS" == "Ready" ]]; then
            STATUS_ICON="✅"
            [ "$NODE_ROLE" == "edge" ] && EDGE_READY=$((EDGE_READY+1))
            PASSED=$((PASSED+1))
            log "  ${GREEN}✓${NC} 节点 $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
        else
            STATUS_ICON="❌"
            FAILED=$((FAILED+1))
            log "  ${RED}✗${NC} 节点 $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
        fi

        SECTION_HTML+="<tr><td>$STATUS_ICON</td><td>$NODE_NAME</td><td>$NODE_STATUS</td><td>$NODE_ROLE</td></tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "${RED}❌ 无法获取 K8s 节点信息${NC}"
    FAILED=$((FAILED+1))
fi

EDGE_ONLINE_RATE=$(( EDGE_COUNT>0 ? EDGE_READY*100/EDGE_COUNT : 0 ))

# ================= 服务器基础信息 =================
HOSTNAME=$(hostname)
CPU_CORES=$(nproc)
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
DISK_TOTAL=$(df / | awk 'NR==2 {print $2}')
OS_VERSION=$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')
KERNEL_VERSION=$(uname -r)
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')

TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

# ================= 生成 HTML 报告 =================
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>AI员工 - 人工智能Agent工厂</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: Arial; background:#f4f6f9; padding:30px; }
.container { background:white; padding:25px; border-radius:10px; }
h1 { font-size:28px; margin-bottom:5px; }
.subtitle { font-size:14px; color:#555; margin-bottom:20px; padding:8px 12px;
border-left:4px solid #1a73e8; border-radius:6px; background:linear-gradient(90deg,#f1f3f5,#ffffff);}
.score { font-size:40px; font-weight:bold; text-align:center; color:#28a745; margin-bottom:15px; }
.card-grid { display:flex; gap:15px; margin-bottom:20px; }
.card { flex:1; background:#f1f3f5; padding:15px; border-radius:6px; text-align:center; }
table { width:100%; border-collapse:collapse; margin-top:15px; }
th, td { border:1px solid #ddd; padding:8px; font-size:13px; }
th { background:#eee; }
.chart-row { display:flex; gap:20px; margin-top:20px; }
.chart-box { flex:1; height:100px; }
canvas { height:100px !important; }
</style>
</head>
<body>
<div class="container">

<h1>🤖 AI员工 - 人工智能Agent工厂</h1>
<div class="subtitle">企业级-边缘机器人智慧工程-智能体基础设施健康监控平台</div>

<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
<p>控制节点: $CONTROL_IP</p>

<div class="score">$HEALTH_SCORE%</div>

<div class="card-grid">
<div class="card">NAS 状态<br><b>$NAS_STATUS</b></div>
<div class="card">核心节点<br><b>$CORE_COUNT</b></div>
<div class="card">工作节点<br><b>$WORKER_COUNT</b></div>
<div class="card">边缘在线率<br><b>${EDGE_ONLINE_RATE}%</b></div>
</div>

<h3>🖥 服务器基本配置</h3>
<table>
<tr><th>项目</th><th>值</th></tr>
<tr><td>主机名</td><td>$HOSTNAME</td></tr>
<tr><td>CPU 核心数</td><td>$CPU_CORES</td></tr>
<tr><td>内存总量</td><td>$MEM_TOTAL</td></tr>
<tr><td>系统磁盘</td><td>$DISK_TOTAL</td></tr>
<tr><td>操作系统</td><td>$OS_VERSION</td></tr>
<tr><td>内核版本</td><td>$KERNEL_VERSION</td></tr>
<tr><td>Kubernetes版本</td><td>$K8S_VERSION</td></tr>
</table>

<h3>📋 节点详情</h3>
<table>
<tr><th>状态</th><th>节点</th><th>状态</th><th>分类</th></tr>
$SECTION_HTML
</table>

<h3>📊 节点分布与在线率</h3>
<div class="chart-row">
    <div class="chart-box"><canvas id="nodeChart"></canvas></div>
    <div class="chart-box"><canvas id="edgeChart"></canvas></div>
</div>

<script>
new Chart(document.getElementById('nodeChart'), {
type: 'pie',
data: {
labels: ['核心','工作','边缘'],
datasets: [{
data: [$CORE_COUNT, $WORKER_COUNT, $EDGE_COUNT],
backgroundColor: ['#1a73e8','#34a853','#fbbc05']
}]
},
options: { maintainAspectRatio:false }
});

new Chart(document.getElementById('edgeChart'), {
type: 'doughnut',
data: {
labels: ['在线','离线'],
datasets: [{
data: [$EDGE_READY, $((EDGE_COUNT-EDGE_READY))],
backgroundColor: ['#28a745','#dc3545']
}]
},
options: { maintainAspectRatio:false }
});
</script>

</div>
</body>
</html>
EOF

log "${GREEN}✅ 企业级 KubeEdge 健康报告生成完成${NC}"
log "  👉 HTML报告: $REPORT_FILE"
log "  👉 日志文件: $LOG_FILE"
