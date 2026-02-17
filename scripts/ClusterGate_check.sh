#!/bin/bash
# ====================================================================
# 🔹 ClusterGate 本机端口 & 节点状态检查
# 只关注本机端口，带详细调试输出
# ====================================================================

set -euo pipefail
set -x  # 开启命令跟踪，方便定位问题

# ---------------- 配置 ----------------
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

LOG_FILE="/tmp/ClusterGate_check_${TIMESTAMP}.log"
PORTS=(6443 10000 10002 8080 443)

log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"; }

# ---------------- 环境检查 ----------------
command -v nc >/dev/null 2>&1 || {
    log "nc 命令不存在，自动安装..."
    if command -v apt >/dev/null; then
        sudo apt update && sudo apt install -y netcat
    elif command -v yum >/dev/null; then
        sudo yum install -y nc
    else
        log "无法自动安装 nc，请手动安装"
        exit 1
    fi
}

# ---------------- 节点信息 ----------------
log "🔹 获取节点信息..."
kubectl get nodes -o wide | tee -a "$LOG_FILE"

for node in $(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name); do
    STATUS=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    IP=$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
    log "节点: $node | IP: $IP | Ready状态: $STATUS"
done

# ---------------- 本机端口检查 ----------------
log "🔹 检查本机 TCP 端口..."
for PORT in "${PORTS[@]}"; do
    if nc -z -w 2 localhost "$PORT" &>/dev/null; then
        log "端口 $PORT: ✅ 可达"
    else
        log "端口 $PORT: ❌ 不可达"
    fi
done

log "🔹 检查完成，日志文件: $LOG_FILE"
