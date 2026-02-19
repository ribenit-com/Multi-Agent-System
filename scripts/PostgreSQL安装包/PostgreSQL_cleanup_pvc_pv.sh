#!/bin/bash
# ===================================================
# 脚本名称: cleanup_init_postgresql_enterprise.sh
# 功能: PostgreSQL HA 企业生产级清理与规范化 PVC 初始化
#      - 自动同步 HA 副本
#      - StatefulSet 活动检测
#      - PVC 删除前提示备份
#      - 日志文件记录
#      - Dry Run 模式安全预览
# ===================================================

set -Eeuo pipefail

# ------------------------------
# 1. 配置（可通过环境变量覆盖）
# ------------------------------
NAMESPACE=${NAMESPACE:-ns-mid-storage}
APP_LABEL=${APP_LABEL:-postgres}
PVC_SIZE=${PVC_SIZE:-20Gi}
STORAGE_CLASS=${STORAGE_CLASS:-sc-ssd-high}
DRY_RUN=${DRY_RUN:-true}                    # true=预览不执行
LOG_FILE="postgres_cleanup_$(date +%Y%m%d_%H%M%S).log"

PVC_PREFIX="pvc-pg-data-"

# ------------------------------
# 2. 日志函数
# ------------------------------
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

exec_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "🔍 [DRY-RUN] 将执行: $*"
    else
        log "⚡ 执行: $*"
        eval "$*"
    fi
}

log "---------------------------------------------------"
log "🚀 PostgreSQL 企业级资源清理初始化"
log "📍 Namespace: $NAMESPACE"
log "🛡 Dry Run: $DRY_RUN"
log "🛠 StorageClass: $STORAGE_CLASS"
log "---------------------------------------------------"

# ------------------------------
# 3. 权限与 Namespace 检查
# ------------------------------
kubectl get ns "$NAMESPACE" &>/dev/null || { log "❌ Namespace $NAMESPACE 不存在"; exit 1; }

# ------------------------------
# 4. HA 副本自动检测
# ------------------------------
STS_NAME=$(kubectl get sts -n "$NAMESPACE" -l app="$APP_LABEL" -o name || true)
if [[ -n "$STS_NAME" ]]; then
    HA_REPLICAS=$(kubectl get sts "$STS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    log "ℹ️ 检测到 StatefulSet $STS_NAME，HA 副本数自动同步: $HA_REPLICAS"
else
    HA_REPLICAS=${HA_REPLICAS:-3}
    log "ℹ️ 未检测到 StatefulSet，使用默认 HA 副本: $HA_REPLICAS"
fi

# ------------------------------
# 5. StatefulSet 安全删除
# ------------------------------
if [[ -n "$STS_NAME" ]]; then
    log "=== Step 0: 检查 StatefulSet 活动 ==="
    ACTIVE_PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_LABEL" -o name)
    if [[ -n "$ACTIVE_PODS" ]]; then
        log "⚠️ 检测到正在运行的 Pod:"
        echo "$ACTIVE_PODS" | tee -a "$LOG_FILE"
        log "💡 建议先备份数据或快照"
    fi
    log "=== 删除 StatefulSet ==="
    exec_cmd "kubectl delete $STS_NAME -n $NAMESPACE --cascade=foreground"
else
    log "✅ 未发现 StatefulSet"
fi

# ------------------------------
# 6. PVC 检查与清理
# ------------------------------
log "=== Step 1: 清理不规范 PVC ==="
CURRENT_PVCS=$(kubectl get pvc -n "$NAMESPACE" -l app="$APP_LABEL" -o jsonpath='{.items[*].metadata.name}')
for pvc in $CURRENT_PVCS; do
    if [[ "$pvc" =~ ^$PVC_PREFIX[0-9]+$ ]]; then
        idx=${pvc#$PVC_PREFIX}
        if [ "$idx" -lt "$HA_REPLICAS" ]; then
            log "✅ PVC $pvc 符合规范且在副本范围内，保留"
            continue
        else
            log "🗑 PVC $pvc 超出副本范围，准备删除"
        fi
    else
        log "🗑 PVC $pvc 命名不合规，准备删除"
    fi
    log "💾 请确保已备份 PVC $pvc 数据"
    exec_cmd "kubectl delete pvc $pvc -n $NAMESPACE"
done

# ------------------------------
# 7. 初始化规范 PVC
# ------------------------------
log "=== Step 2: 创建标准 HA PVC ==="
for i in $(seq 0 $((HA_REPLICAS-1))); do
    PVC_NAME="${PVC_PREFIX}${i}"
    if kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        log "🆗 PVC $PVC_NAME 已存在"
    else
        log "➕ 创建 PVC $PVC_NAME"
        if [[ "$DRY_RUN" == "false" ]]; then
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
  labels:
    app: $APP_LABEL
    infra/project: enterprise-ai
    infra/node-type: data
spec:
  storageClassName: $STORAGE_CLASS
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
EOF
        else
            log "🔍 [DRY-RUN] 将创建 PVC $PVC_NAME (Size: $PVC_SIZE, SC: $STORAGE_CLASS)"
        fi
    fi
done

# ------------------------------
# 8. 孤儿 PV 清理
# ------------------------------
log "=== Step 3: 清理孤儿 PV (Released) ==="
ORPHAN_PVS=$(kubectl get pv -o json | jq -r ".items[] | select(.status.phase==\"Released\" and .spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name")
for pv in $ORPHAN_PVS; do
    log "🧹 孤儿 PV $pv 将被删除"
    exec_cmd "kubectl delete pv $pv"
done

# ------------------------------
# 完成提示
# ------------------------------
log "---------------------------------------------------"
log "✅ PostgreSQL HA 企业级清理与 PVC 初始化完成"
if [[ "$DRY_RUN" == "true" ]]; then
    log "💡 提示: 当前处于 Dry-Run 模式，如需执行，请运行: DRY_RUN=false bash $0"
fi
log "📄 日志文件: $LOG_FILE"
