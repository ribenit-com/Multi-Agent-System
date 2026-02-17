#!/bin/bash
# ==============================================================================
# AI员工 - 人工智能Agent工厂
# 企业级-边缘机器人智慧工程-智能体基础设施健康监控平台 v3
# ==============================================================================

export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

NAS_DIR="/mnt/truenas"
REPORT_FILE="${NAS_DIR}/ai-agent-factory-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_DIR}/ai-agent-factory-log-${TIMESTAMP}.log"

# ================= 初始化 =================
mkdir -p "$NAS_DIR" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null || { echo "❌ NAS 不可写"; exit 1; }

PASSED=0
FAILED=0
CORE_COUNT=0
WORKER_COUNT=0
EDGE_COUNT=0
EDGE_READY=0

SECTION_HTML=""

log() { echo "$1" | tee -a "$LOG_FILE"; }

echo "════════════ AI员工-人工智能Agent工厂 健康检测 v3 ════════════" | tee -a "$LOG_FILE"

# ==============================================================================
# 1️⃣ NAS 挂载检测
# ==============================================================================
log ""
log "[1/4] NAS 挂载检测"

NAS_STATUS="正常"
TEST_FILE="$NAS_DIR/test_$$.txt"

if mountpoint -q "$NAS_DIR"; then
    log "✓ NAS 已挂载"
    PASSED=$((PASSED+1))
else
    log "❌ NAS 未挂载"
    NAS_STATUS="未挂载"
    FAILED=$((FAILED+1))
fi

if echo "test $(date)" > "$TEST_FILE" 2>/dev/null; then
    log "✓ NAS 可写"
    rm -f "$TEST_FILE"
    PASSED=$((PASSED+1))
else
    log "❌ NAS 无写权限"
    NAS_STATUS="不可写"
    FAILED=$((FAILED+1))
fi

# ==============================================================================
# 2️⃣ 节点分类检测
# ==============================================================================
log ""
log "[2/4] 节点分类检测"

if kubectl get nodes &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')

        if [[ "$NODE_ROLE" == *"control-plane"* ]] || [[ "$NODE_ROLE" == *"master"* ]]; then
            CATEGORY="🏛 K8s核心节点"
            CORE_COUNT=$((CORE_COUNT+1))
        elif [[ "$NODE_ROLE" == *"edge"* ]] || [[ "$NODE_ROLE" == *"agent"* ]]; then
            CATEGORY="🌐 KubeEdge边缘节点"
            EDGE_COUNT=$((EDGE_COUNT+1))
        else
            CATEGORY="🖥 K8s工作节点"
            WORKER_COUNT=$((WORKER_COUNT+1))
        fi

        if [[ "$NODE_STATUS" == "Ready" ]]; then
            ICON="✅"
            PASSED=$((PASSED+1))
            if [[ "$CATEGORY" == *"边缘"* ]]; then
                EDGE_READY=$((EDGE_READY+1))
            fi
        else
            ICON="❌"
            FAILED=$((FAILED+1))
        fi

        SECTION_HTML+="
        <tr>
            <td>$ICON</td>
            <td>$NODE_NAME</td>
            <td>$NODE_STATUS</td>
            <td>$CATEGORY</td>
        </tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "❌ 无法连接 Kubernetes 集群"
    FAILED=$((FAILED+1))
fi

TOTAL_CHECKS=$((PASSED+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))
EDGE_ONLINE_RATE=$(( EDGE_COUNT>0 ? EDGE_READY*100/EDGE_COUNT : 100 ))

# ==============================================================================
# 3️⃣ 生成企业级 HTML 报告
# ==============================================================================
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>AI员工 - 人工智能Agent工厂</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: Arial; background:#f4f6f9; padding:40px; }
.container { background:white; padding:30px; border-radius:10px; }
h1 { font-size:32px; margin-bottom:5px; }
.subtitle {
    font-size:15px;
    color:#555;
    margin-bottom:25px;
    padding:10px 15px;
    background:linear-gradient(90deg,#f1f3f5,#ffffff);
    border-left:4px solid #1a73e8;
    border-radius:6px;
}
.score { font-size:50px; font-weight:bold; text-align:center; color:#28a745; }
.card-grid { display:flex; gap:20px; margin:20px 0; }
.card { flex:1; background:#f1f3f5; padding:20px; border-radius:8px; text-align:center; }
table { width:100%; border-collapse:collapse; margin-top:20px; }
th, td { border:1px solid #ddd; padding:10px; }
th { background:#eee; }
canvas { margin-top:30px; }
</style>
</head>
<body>
<div class="container">

<h1>🤖 AI员工 - 人工智能Agent工厂</h1>
<div class="subtitle">
企业级-边缘机器人智慧工程-智能体基础设施健康监控平台
</div>

<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
<p>控制节点: $CONTROL_IP</p>

<div class="score">$HEALTH_SCORE%</div>

<div class="card-grid">
<div class="card">NAS 状态<br><b>$NAS_STATUS</b></div>
<div class="card">核心节点<br><b>$CORE_COUNT</b></div>
<div class="card">工作节点<br><b>$WORKER_COUNT</b></div>
<div class="card">边缘在线率<br><b>${EDGE_ONLINE_RATE}%</b></div>
</div>

<h3>节点详情</h3>
<table>
<tr><th>状态</th><th>节点</th><th>状态</th><th>分类</th></tr>
$SECTION_HTML
</table>

<h3>节点分类分布</h3>
<canvas id="nodeChart"></canvas>

<h3>边缘在线率</h3>
<canvas id="edgeChart"></canvas>

<script>
new Chart(document.getElementById('nodeChart'), {
type: 'pie',
data: {
labels: ['核心节点','工作节点','边缘节点'],
datasets: [{
data: [$CORE_COUNT, $WORKER_COUNT, $EDGE_COUNT],
backgroundColor: ['#1a73e8','#34a853','#fbbc05']
}]
}
});

new Chart(document.getElementById('edgeChart'), {
type: 'doughnut',
data: {
labels: ['在线','离线'],
datasets: [{
data: [$EDGE_READY, $((EDGE_COUNT-EDGE_READY))],
backgroundColor: ['#28a745','#dc3545']
}]
}
});
</script>

</div>
</body>
</html>
EOF

log ""
log "✅ 企业级 v3 报告已生成"
log "HTML: $REPORT_FILE"
log "日志: $LOG_FILE"
