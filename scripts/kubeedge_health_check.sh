#!/bin/bash
# ==============================
# 🤖 AI员工 - 企业级健康监控平台
# 调试版 v5-debug
# 输出: HTML报告 + 日志 + 详细调试信息
# ==============================

set -euo pipefail

export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

NAS_LOG_DIR="/mnt/truenas"
mkdir -p "$NAS_LOG_DIR"

REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""

log() { echo -e "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

log "${BLUE}=== 开始健康检测 ===${NC}"

# ---------------- NAS检测 ----------------
log "检测 NAS 挂载..."
NAS_STATUS="❌ 未挂载"; NAS_WRITABLE="否"; NAS_USAGE="N/A"
if [ -d "$NAS_LOG_DIR" ]; then
    NAS_STATUS="✅ 挂载成功"
    [ -w "$NAS_LOG_DIR" ] && NAS_WRITABLE="是"
    NAS_USAGE=$(df -h "$NAS_LOG_DIR" | awk 'NR==2 {print $5}')
fi
log "NAS状态: $NAS_STATUS, 可写: $NAS_WRITABLE, 使用率: $NAS_USAGE"
SECTION_HTML+="<tr><td>$NAS_STATUS</td><td>NAS挂载</td><td>可写: $NAS_WRITABLE, 使用率: $NAS_USAGE</td><td>-</td></tr>"

# ---------------- 硬件信息 ----------------
log "获取服务器硬件信息..."
CPU_CORES=$(nproc)
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_USAGE=$(df -h / | awk 'NR==2{print $5}')
log "CPU: $CPU_CORES 核心, 内存: $MEM_TOTAL ($MEM_USAGE%), 磁盘: $DISK_TOTAL ($DISK_USAGE%)"
SECTION_HTML+="<tr><td>✅</td><td>服务器硬件</td><td>CPU: $CPU_CORES 核心, 内存: $MEM_TOTAL ($MEM_USAGE%), 磁盘: $DISK_TOTAL ($DISK_USAGE%)</td><td>-</td></tr>"

# ---------------- Kubernetes版本 ----------------
log "获取 Kubernetes 版本..."
K8S_VERSION=$(kubectl version --short --request-timeout=5s 2>/dev/null | grep Server | awk '{print $3}' || echo "未知")
log "Kubernetes版本: $K8S_VERSION"
SECTION_HTML+="<tr><td>✅</td><td>Kubernetes版本</td><td>$K8S_VERSION</td><td>-</td></tr>"

# ---------------- 节点状态 ----------------
log "获取节点状态..."
if kubectl get nodes --no-headers --request-timeout=5s &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')
        NODE_TYPE=$( [[ "$NODE_NAME" =~ master ]] && echo "控制中心" || echo "边缘节点" )
        NODE_SOFTWARE="未知"
        log "节点: $NODE_NAME | 状态: $NODE_STATUS | 类型: $NODE_TYPE"
        SECTION_HTML+="<tr><td>✅</td><td>$NODE_NAME ($NODE_TYPE)</td><td>$NODE_STATUS</td><td>软件类型: $NODE_SOFTWARE</td></tr>"
    done < <(kubectl get nodes --no-headers --request-timeout=5s)
else
    log "${RED}❌ 无法获取节点信息${NC}"
fi

# ---------------- 端口检查 ----------------
log "检查核心端口..."
for PORT in 6443 10000 10002 8080 443; do
    log "检测端口 $PORT ..."
    if nc -z -w 2 localhost $PORT &>/dev/null; then
        log "端口 $PORT 可达"
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>-</td></tr>"
    else
        log "${RED}端口 $PORT 不可达${NC}"
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>不可达</td><td>检查服务</td></tr>"
    fi
done

# ---------------- Pod检查 ----------------
log "检查 Pod 状态..."
for ns in kube-system argocd default; do
    log "命名空间: $ns"
    POD_LIST=$(kubectl get pods -n "$ns" --no-headers --request-timeout=5s 2>/dev/null || echo "")
    if [ -n "$POD_LIST" ]; then
        while read -r line; do
            POD_NAME=$(echo $line | awk '{print $1}')
            STATUS=$(echo $line | awk '{print $3}')
            RESTARTS=$(echo $line | awk '{print $4}')
            log "Pod: $POD_NAME | 状态: $STATUS | 重启: $RESTARTS"
            SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )</td><td>$POD_NAME (ns:$ns)</td><td>状态: $STATUS, 重启次数: $RESTARTS</td><td>-</td></tr>"
        done <<< "$POD_LIST"
    else
        log "${RED}无法获取 Pod 信息 (ns:$ns)${NC}"
        SECTION_HTML+="<tr><td>❌</td><td>命名空间: $ns</td><td>无法获取 Pod 信息</td><td>-</td></tr>"
    fi
done

# ---------------- PVC检查 ----------------
log "检查 PVC..."
PVC_LIST=$(kubectl get pvc -n argocd --no-headers --request-timeout=5s 2>/dev/null || echo "")
if [ -n "$PVC_LIST" ]; then
    while read -r pvc; do
        NAME=$(echo $pvc | awk '{print $1}')
        STATUS=$(kubectl get pvc "$NAME" -n argocd -o jsonpath='{.status.phase}' 2>/dev/null || echo "未知")
        log "PVC: $NAME | 状态: $STATUS"
        SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Bound" ]] && echo "✅" || echo "❌" )</td><td>$NAME</td><td>状态: $STATUS</td><td>-</td></tr>"
    done <<< "$PVC_LIST"
fi

# ---------------- K8s核心组件 ----------------
log "检查核心组件..."
for comp in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    POD=$(kubectl get pod -n kube-system --request-timeout=5s 2>/dev/null | grep "$comp" || echo "")
    if [ -n "$POD" ]; then
        STATUS=$(echo "$POD" | awk '{print $3}')
        log "组件: $comp | 状态: $STATUS"
        SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )</td><td>$comp</td><td>状态: $STATUS</td><td>-</td></tr>"
    else
        log "${RED}组件 $comp Pod 未发现${NC}"
        SECTION_HTML+="<tr><td>❌</td><td>$comp</td><td>Pod 未发现</td><td>检查部署</td></tr>"
    fi
done

# ---------------- HTML报告 ----------------
log "生成 HTML 报告..."
cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>🤖 AI员工 - 企业级健康监控平台</title>
<style>
body { font-family: 'Segoe UI', sans-serif; margin: 40px; background: #f0f2f5; }
.card { background: white; padding: 20px; border-radius: 8px; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
th { background: #f8f9fa; font-weight: bold; }
</style>
</head>
<body>
<div class="card">
<h1>🤖 AI员工 - 企业级健康监控平台</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 控制中心: $CONTROL_IP</p>
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
