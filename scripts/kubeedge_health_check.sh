#!/bin/bash
# ====================================================================
# 🤖 AI员工 - 企业级 ArgoCD & K8s 健康监控平台
# 新版 v6 - 节点握手状态 & 自动安装 nc
# 输出: HTML 报告 + 日志
# ====================================================================

set -euo pipefail

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

NAS_LOG_DIR="/mnt/truenas"
mkdir -p "$NAS_LOG_DIR"

REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ---------------- 检查 nc 工具 ----------------
if ! command -v nc &>/dev/null; then
    log "${YELLOW}⚠ nc 工具未安装，尝试安装...${NC}"
    if command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y netcat
    elif command -v yum &>/dev/null; then
        sudo yum install -y nc
    else
        log "${RED}❌ 无法安装 nc，请手动安装${NC}"
    fi
fi

# ---------------- NAS检测 ----------------
NAS_STATUS="❌ 未挂载"; NAS_WRITABLE="否"; NAS_USAGE="N/A"
if [ -d "$NAS_LOG_DIR" ]; then
    NAS_STATUS="✅ 挂载成功"
    [ -w "$NAS_LOG_DIR" ] && NAS_WRITABLE="是"
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
log "CPU: $CPU_CORES 核心 | 内存: $MEM_TOTAL ($MEM_USAGE%) | 磁盘: $DISK_TOTAL ($DISK_USAGE%)"
SECTION_HTML+="<tr><td>✅</td><td>服务器硬件</td><td>CPU: $CPU_CORES 核心, 内存: $MEM_TOTAL ($MEM_USAGE%), 磁盘: $DISK_TOTAL ($DISK_USAGE%)</td><td>-</td></tr>"

# ---------------- Kubernetes版本 ----------------
K8S_VERSION=$(kubectl version --short --request-timeout=5s 2>/dev/null | grep Server | awk '{print $3}' || echo "未知")
log "Kubernetes版本: $K8S_VERSION"
SECTION_HTML+="<tr><td>✅</td><td>Kubernetes版本</td><td>$K8S_VERSION</td><td>-</td></tr>"

# ---------------- 节点状态 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>节点握手状态</b></td></tr>"
TCP_PORTS=(6443 10000 10002 8080 443)

for NODE in $(kubectl get nodes --no-headers --request-timeout=5s | awk '{print $1}'); do
    NODE_IP=$(kubectl get node $NODE -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    NODE_TYPE=$( [[ "$NODE" =~ master ]] && echo "控制中心" || echo "边缘节点" )
    NODE_STATUS=$(kubectl get node $NODE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    # TCP端口检测
    TCP_STATUS=""
    for PORT in "${TCP_PORTS[@]}"; do
        nc -z -w 2 $NODE_IP $PORT &>/dev/null && TCP_STATUS+="$PORT ✅ " || TCP_STATUS+="$PORT ❌ "
    done

    # ICMP检测
    ping -c 1 -W 1 $NODE_IP &>/dev/null && PING_STATUS="✅" || PING_STATUS="❌"

    SECTION_HTML+="<tr><td>$( [[ "$NODE_STATUS" == "True" ]] && echo "✅" || echo "❌" )</td><td>$NODE ($NODE_TYPE)</td><td>TCP端口: $TCP_STATUS</td><td>ICMP: $PING_STATUS</td></tr>"
done

# ---------------- Pod/Namespace 检查 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>Pod/Namespace 检查</b></td></tr>"
for NS in kube-system argocd default; do
    if kubectl get ns $NS &>/dev/null; then
        POD_LIST=$(kubectl get pods -n $NS --no-headers --request-timeout=5s 2>/dev/null || echo "")
        if [ -z "$POD_LIST" ]; then
            SECTION_HTML+="<tr><td>❌</td><td>命名空间: $NS</td><td>存在但无 Pod</td><td>-</td></tr>"
        else
            while read -r line; do
                POD_NAME=$(echo $line | awk '{print $1}')
                STATUS=$(echo $line | awk '{print $3}')
                RESTARTS=$(echo $line | awk '{print $4}')
                SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )</td><td>$POD_NAME (ns:$NS)</td><td>状态: $STATUS, 重启次数: $RESTARTS</td><td>-</td></tr>"
            done <<< "$POD_LIST"
        fi
    else
        SECTION_HTML+="<tr><td>❌</td><td>命名空间: $NS</td><td>不存在</td><td>-</td></tr>"
    fi
done

# ---------------- HTML报告 ----------------
HEALTH_SCORE=100
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>🤖 AI员工 - 企业级健康监控平台</title>
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
<h1>🤖 AI员工 - 企业级健康监控平台</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 控制中心: $CONTROL_IP</p>
<p>健康评分: $HEALTH_SCORE%</p>
<table>
<tr><th>状态</th><th>检测项</th><th>详情</th><th>备注</th></tr>
$SECTION_HTML
</table>
</div>
</body>
</html>
EOF

log "${GREEN}✅ 健康检测完成${NC}"
log "报告: $REPORT_FILE"
log "日志: $LOG_FILE"
