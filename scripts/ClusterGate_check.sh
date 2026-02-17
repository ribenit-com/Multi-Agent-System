#!/bin/bash
# ====================================================================
# 🔹 ClusterGate 健康检测
# 企业级 KubeEdge/ArgoCD 节点状态 + 本机端口 + Pod/命名空间检查
# ====================================================================

set -euo pipefail

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

LOG_FILE="/tmp/ClusterGate_check-${TIMESTAMP}.log"
echo "ClusterGate 检测日志 - $TIMESTAMP" | tee -a "$LOG_FILE"

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ---------------- 本机端口检测 ----------------
PORTS=(6443 10000 10002 8080 443)
log "\n🔹 本机端口检测:"
for PORT in "${PORTS[@]}"; do
    if nc -z -w 2 localhost $PORT &>/dev/null; then
        log "✅ 端口 $PORT 可达"
    else
        log "❌ 端口 $PORT 不可达"
    fi
done

# ---------------- 节点状态 ----------------
log "\n🔹 节点状态:"
NODE_LIST=$(kubectl get nodes -o custom-columns=NAME:.metadata.name,IP:.status.addresses[?(@.type=='InternalIP')].address,STATUS:.status.conditions[-1].type,READY:.status.conditions[-1].status --no-headers 2>/dev/null || echo "")
if [ -n "$NODE_LIST" ]; then
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_IP=$(echo $line | awk '{print $2}')
        NODE_READY=$(echo $line | awk '{print $4}')
        NODE_TYPE=$( [[ "$NODE_NAME" =~ master ]] && echo "控制中心" || echo "边缘节点" )
        ICMP_STATUS=$(ping -c 1 -W 1 $NODE_IP &>/dev/null && echo "✅" || echo "❌")
        log "$NODE_NAME ($NODE_TYPE) | IP: $NODE_IP | Ready: $NODE_READY | ICMP: $ICMP_STATUS"
    done <<< "$NODE_LIST"
else
    log "❌ 无法获取节点信息"
fi

# ---------------- Pod / 命名空间 ----------------
NAMESPACES=("kube-system" "argocd" "default")
log "\n🔹 Pod/Deployment 健康检查:"
for ns in "${NAMESPACES[@]}"; do
    POD_LIST=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null || echo "")
    if [ -z "$POD_LIST" ]; then
        # 判断命名空间是否存在
        kubectl get ns "$ns" &>/dev/null
        if [ $? -eq 0 ]; then
            log "❌ 命名空间: $ns 存在，但无 Pod"
        else
            log "❌ 命名空间: $ns 无法获取 Pod 信息"
        fi
    else
        while read -r line; do
            POD_NAME=$(echo $line | awk '{print $1}')
            STATUS=$(echo $line | awk '{print $3}')
            RESTARTS=$(echo $line | awk '{print $4}')
            STATUS_ICON=$( [[ "$STATUS" == "Running" ]] && echo "✅" || echo "❌" )
            log "$STATUS_ICON $POD_NAME (ns:$ns) | 状态: $STATUS, 重启次数: $RESTARTS"
        done <<< "$POD_LIST"
    fi
done

log "\n🔹 检测完成. 日志: $LOG_FILE"
