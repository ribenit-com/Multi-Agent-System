#!/bin/bash
# ===================================================
# 脚本名称: cleanup_init_postgresql_auto.sh
# 功能: PostgreSQL HA 全自动清理与标准化 PVC 初始化
#      - Namespace 不存在自动创建
#      - 强制标准化命名 pvc-pg-data-n
#      - 支持 Dry-Run 模式
#      - 自动关联 StorageClass
#      - 安全删除 StatefulSet 与孤儿 PV
# ===================================================

set -Eeuo pipefail

# ------------------------------
# 默认配置（可通过环境变量覆盖）
# ------------------------------
NAMESPACE=${NAMESPACE:-ns-mid-storage}
APP_LABEL=${APP_LABEL:-postgres}
PVC_SIZE=${PVC_SIZE:-20Gi}
STORAGE_CLASS=${STORAGE_CLASS:-sc-ssd-high}
DRY_RUN=${DRY_RUN:-true}

PVC_PREFIX="pvc-pg-data-"

LOG_FILE="postgres_cleanup_$(date +%Y%m%d_%H%M%S).log"

# ------------------------------
# 日志函数
# ------------------------------
log() {
    echo "$(date +%F\ %T) $1" | tee -a "$LOG_FILE"
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
log "🚀 PostgreSQL 企业级全自动资源清理初始化"
log "📍 Namespace: $NAMESPACE"
log "🛡 Dry Run: $DRY_RUN"
log "🛠 StorageClass: $STORAGE_CLASS"
log "---------------------------------------------------"

# ------------------------------
# 1. 自动创建 Namespace
# ------------------------------
if ! kubectl get ns "$NAMESPACE" &>/dev/null; then
    log "⚠️ Namespace $NAMESPACE 不存在，正在创建"
    exec_cmd "kubectl create namespace $NAMESPACE"
else
    log "✅ Namespace $NAMESPACE 已存在"
fi

# ------------------------------
# 2. HA 副本检测
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
# 3. StatefulSet 删除
# ------------------------------
if [[ -n "$STS_NAME" ]]; then
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
# 4. PVC 清理
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
# 5. PVC 初始化
# ------------------------------
log "=== Step 2: 初始化标准 HA PVC ==="
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
# 6. 孤儿 PV 清理
# ------------------------------
log "=== Step 3: 清理孤儿 PV (Released) ==="
ORPHAN_PVS=$(kubectl get pv -o json | jq -r ".items[] | select(.status.phase==\"Released\" and .spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name")
for pv in $ORPHAN_PVS; do
    log "🧹 孤儿 PV $pv 将被删除"
    exec_cmd "kubectl delete pv $pv"
done

# ------------------------------
# 7. 完成提示
# ------------------------------
log "---------------------------------------------------"
log "✅ PostgreSQL HA 全自动标准化完成"
if [[ "$DRY_RUN" == "true" ]]; then
    log "💡 提示: 当前为 Dry-Run 模式，如需执行，请运行: DRY_RUN=false bash $0"
fi
log "📄 日志文件: $LOG_FILE"
