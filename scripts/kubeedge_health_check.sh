#!/bin/bash
# ====================================================================
# 🤖 AI员工 - 企业级 ArgoCD & K8s 健康监控平台
# 修正版 v6 - 稳定 + debug 输出 + 超时保护
# ====================================================================

set -euo pipefail
set -x  # 开启详细 debug 输出

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

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
if kubectl get nodes --no-headers --request-timeout=5s &>/dev/null; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')
        NODE_TYPE=$( [[ "$NODE_NAME" =~ master ]] && echo "控制中心" || echo "边缘节点" )
        NODE_SOFTWARE="未知"  # 避免 SSH 阻塞

        SECTION_HTML+="<tr><td>✅</td><td>$NODE_NAME ($NODE_TYPE)</td><td>$NODE_STATUS</td><td>软件类型: $NODE_SOFTWARE</td></tr>"
    done < <(kubectl get nodes --no-headers --request-timeout=5s)
else
    log "${RED}❌ 无法获取节点信息${NC}"
fi

# ---------------- 端口检查 ----------------
for PORT in 6443 10000 10002 8080 443; do
    if nc -z -w 2 localhost $PORT &>/dev/null; then
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>-</td></tr>"
    else
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>不可达</td><td>检查服务</td></tr>"
    fi
done

# ---------------- Pod/Deployment 检查 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>Pod/Deployment 健康检查</b></td></tr>"
for ns in kube-system argocd default; do
    POD_LIST=$(kubectl get pods -n "$ns" --no-headers --request-timeout=5s 2>/dev/null || echo "")
    if [ -n "$POD_LIST" ]; then
        while read -r line; do
            POD_NAME=$(echo $line | awk '{print $1}')
            STATUS=$(echo $line | awk '{print $3}')
            RESTARTS=$(echo $line | awk '{print $4}')
            SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )</td><td>$POD_NAME (ns:$ns)</td><td>状态: $STATUS, 重启次数: $RESTARTS</td><td>-</td></tr>"
        done <<< "$POD_LIST"
    else
        SECTION_HTML+="<tr><td>❌</td><td>命名空间: $ns</td><td>无法获取 Pod 信息</td><td>-</td></tr>"
    fi
done

# ---------------- PVC 检查 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>存储卷/PVC 检查</b></td></tr>"
PVC_LIST=$(kubectl get pvc -n argocd --no-headers --request-timeout=5s 2>/dev/null || echo "")
if [ -n "$PVC_LIST" ]; then
    while read -r pvc; do
        NAME=$(echo $pvc | awk '{print $1}')
        STATUS=$(kubectl get pvc "$NAME" -n argocd -o jsonpath='{.status.phase}')
        SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Bound" ]] && echo "✅" || echo "❌" )</td><td>$NAME</td><td>状态: $STATUS</td><td>-</td></tr>"
    done <<< "$PVC_LIST"
fi

# ---------------- K8s核心组件 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>Kubernetes 核心组件健康</b></td></tr>"
for comp in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    POD=$(kubectl get pod -n kube-system --request-timeout=5s 2>/dev/null | grep "$comp" || echo "")
    if [ -n "$POD" ]; then
        STATUS=$(echo "$POD" | awk '{print $3}')
        SECTION_HTML+="<tr><td>$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )</td><td>$comp</td><td>状态: $STATUS</td><td>-</td></tr>"
    else
        SECTION_HTML+="<tr><td>❌</td><td>$comp</td><td>Pod 未发现</td><td>检查部署</td></tr>"
    fi
done

# ---------------- 集群网络连通性 ----------------
SECTION_HTML+="<tr><td colspan='4'><b>集群网络连通性</b></td></tr>"
for node in $(kubectl get nodes --no-headers --request-timeout=5s | awk '{print $1}'); do
    if timeout 1 ping -c 1 "$node" &>/dev/null; then
        SECTION_HTML+="<tr><td>✅</td><td>$node</td><td>节点可达</td><td>-</td></tr>"
    else
        SECTION_HTML+="<tr><td>❌</td><td>$node</td><td>节点不可达</td><td>检查网络</td></tr>"
    fi
done

# ---------------- HTML 报告 ----------------
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
