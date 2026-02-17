#!/bin/bash
# ==============================================================================
# KubeEdge 集群全面健康检测脚本 (最终稳定版)
# 日志 & 报告输出到 /mnt/truenas
# ==============================================================================

# ================= 基础配置 =================
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

NAS_LOG_DIR="/mnt/truenas"
REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

# ================= 目录 & 文件初始化 =================
mkdir -p "$NAS_LOG_DIR" || { echo "❌ 无法创建 NAS 目录 $NAS_LOG_DIR"; exit 1; }

touch "$LOG_FILE" || { echo "❌ 无法创建日志文件 $LOG_FILE"; exit 1; }

if [ ! -w "$NAS_LOG_DIR" ]; then
    echo "❌ NAS 路径无写权限: $NAS_LOG_DIR"
    exit 1
fi

# ================= 颜色定义 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ==============================================================================
# 1. 初始化
# ==============================================================================
log "${BLUE}════════════════ KubeEdge 健康检测开始 (${TIMESTAMP}) ════════════════${NC}"
log "中央控制器 IP: $CONTROL_IP"
log ""

# ==============================================================================
# 2. 依赖检查
# ==============================================================================
log "${BLUE}正在检查依赖工具...${NC}"

if ! command -v nc &> /dev/null; then
    log "${YELLOW}未发现 netcat，尝试自动安装...${NC}"
    if [ "$EUID" -ne 0 ]; then
        log "${RED}❌ 需要 root 权限安装，请使用 sudo 运行${NC}"
        exit 1
    fi
    apt-get update && apt-get install -y netcat-openbsd
fi

log "  ${GREEN}✓${NC} netcat 已就绪"
log ""

# ==============================================================================
# 3. 核心检测
# ==============================================================================

# 3.1 端口检测
log "${YELLOW}[1/3] 核心端口检测${NC}"
for PORT in 6443 10000 10002; do
    if nc -z localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 正常"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>服务运行中</td></tr>"
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>失败</td><td>请检查组件</td></tr>"
    fi
done
log ""

# 3.2 系统资源
log "${YELLOW}[2/3] 系统资源检测${NC}"
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

log "  内存使用率: ${MEM_USAGE}%"
log "  磁盘使用率: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -lt 85 ]; then
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>系统磁盘</td><td>${DISK_USAGE}%</td><td>空间正常</td></tr>"
else
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>系统磁盘</td><td>${DISK_USAGE}%</td><td>建议清理</td></tr>"
fi
log ""

# 3.3 K8s 节点检测
log "${YELLOW}[3/3] Kubernetes 节点状态${NC}"

if kubectl get nodes &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')

        if [[ "$NODE_STATUS" == "Ready" ]]; then
            log "  ${GREEN}✓${NC} $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
            PASSED=$((PASSED+1))
            ICON="✅"
        else
            log "  ${RED}✗${NC} $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
            FAILED=$((FAILED+1))
            ICON="❌"
        fi

        SECTION_HTML+="<tr><td>$ICON</td><td>节点: $NODE_NAME</td><td>$NODE_STATUS</td><td>角色: $NODE_ROLE</td></tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "  ${RED}❌ 无法连接 K8s 集群${NC}"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>K8s 连接</td><td>失败</td><td>检查 kubeconfig</td></tr>"
fi

# ==============================================================================
# 4. 生成 HTML 报告
# ==============================================================================
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>KubeEdge 健康报告</title>
<style>
body { font-family: Arial; background:#f4f6f9; padding:40px; }
.card { background:white; padding:20px; border-radius:8px; }
h1 { color:#1a73e8; }
table { width:100%; border-collapse:collapse; margin-top:20px; }
th, td { border:1px solid #ddd; padding:10px; }
th { background:#f2f2f2; }
.score { font-size:48px; font-weight:bold; text-align:center; color:#28a745; }
</style>
</head>
<body>
<div class="card">
<h1>KubeEdge 集群健康报告</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
<p>中央控制器: $CONTROL_IP</p>
<div class="score">$HEALTH_SCORE%</div>
<p>通过: $PASSED | 警告: $WARN | 失败: $FAILED</p>
<table>
<tr><th>状态</th><th>检测项</th><th>详情</th><th>备注</th></tr>
$SECTION_HTML
</table>
</div>
</body>
</html>
EOF

# ==============================================================================
# 5. 结束
# ==============================================================================
log ""
log "${GREEN}✅ 体检完成！${NC}"
log "HTML 报告: $REPORT_FILE"
log "详细日志: $LOG_FILE"
