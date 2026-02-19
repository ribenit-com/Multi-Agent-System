#!/bin/bash
# ==============================================================================
# 脚本名称: cleanup_init_postgresql_enterprise.sh
# 功能描述: PostgreSQL HA 企业生产级清理与规范化 PVC 初始化
#          - 自动同步 HA 副本数 (StatefulSet Replicas)
#          - 执行 StatefulSet 存活 Pod 安全检测
#          - 强制执行企业命名规范: pvc-pg-data-<index>
#          - 自动清理 Released 状态的孤儿 PV
#          - 全程日志审计与 Dry Run 预览模式
# 版本: v2.0.0-enterprise
# 更新时间: 2026-02-19
# ==============================================================================

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
# 2. 核心工具检查
# ------------------------------
command -v jq >/dev/null 2>&1 || { echo "❌ 错误: 系统未安装 jq，清理孤儿 PV 功能受限"; exit 1; }

# ------------------------------
# 3. 日志与执行函数
# ------------------------------
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

exec_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "🔍 [DRY-RUN] 将执行: $*"
    else
        log "⚡ 执行中: $*"
        eval "$*"
    fi
}

log "---------------------------------------------------"
log "🚀 PostgreSQL 企业级资源清理初始化 (Version: v2.0.0)"
log "📍 Namespace: $NAMESPACE"
log "🛡 Dry Run: $DRY_RUN"
log "🛠 StorageClass: $STORAGE_CLASS"
log "---------------------------------------------------"

# ------------------------------
# 4. 环境检查
# ------------------------------
kubectl get ns "$NAMESPACE" &>/dev/null || { log "❌ Namespace $NAMESPACE 不存在"; exit 1; }

# ------------------------------
# 5. HA 副本自动检测
# ------------------------------
STS_NAME=$(kubectl get sts -n "$NAMESPACE" -l app="$APP_LABEL" -o name || true)
if [[ -n "$STS_NAME" ]]; then
    HA_REPLICAS=$(kubectl get sts "$STS_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    log "ℹ️ 检测到现有 StatefulSet，同步副本数: $HA_REPLICAS"
else
    HA_REPLICAS=${HA_REPLICAS:-3}
    log "ℹ️ 未检测到 StatefulSet，使用默认副本数: $HA_REPLICAS"
fi

# ------------------------------
# 6. StatefulSet 安全卸载
# ------------------------------
if [[ -n "$STS_NAME" ]]; then
    log "=== Step 0: 安全检查 StatefulSet ==="
    ACTIVE_PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$APP_LABEL" -o name)
    if [[ -n "$ACTIVE_PODS" ]]; then
        log "⚠️ 注意！以下 Pod 仍在运行，建议先手动备份数据:"
        echo "$ACTIVE_PODS" | tee -a "$LOG_FILE"
    fi
    log "=== 删除 StatefulSet 控制器 ==="
    exec_cmd "kubectl delete $STS_NAME -n $NAMESPACE --cascade=foreground"
else
    log "✅ 环境清洁，未发现冲突的 StatefulSet"
fi

# ------------------------------
# 7. PVC 规范化清理
# ------------------------------

log "=== Step 1: 扫描并清理不规范 PVC ==="
CURRENT_PVCS=$(kubectl get pvc -n "$NAMESPACE" -l app="$APP_LABEL" -o jsonpath='{.items[*].metadata.name}')
for pvc in $CURRENT_PVCS; do
    if [[ "$pvc" =~ ^$PVC_PREFIX[0-9]+$ ]]; then
        idx=${pvc#$PVC_PREFIX}
        if [ "$idx" -lt "$HA_REPLICAS" ]; then
            log "✅ PVC $pvc [合规保留]"
            continue
        else
            log "🗑 PVC $pvc [超出副本范围，标记删除]"
        fi
    else
        log "🗑 PVC $pvc [命名违规，标记删除]"
    fi
    log "💾 警告: 请确保已对 $pvc 完成快照备份"
    exec_cmd "kubectl delete pvc $pvc -n $NAMESPACE"
done

# ------------------------------
# 8. 初始化规范化 PVC
# ------------------------------
log "=== Step 2: 创建标准 HA PVC 资源 ==="
for i in $(seq 0 $((HA_REPLICAS-1))); do
    PVC_NAME="${PVC_PREFIX}${i}"
    if kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
        log "🆗 PVC $PVC_NAME 已经符合规范"
    else
        log "➕ 正在创建标准 PVC: $PVC_NAME"
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
            log "🔍 [DRY-RUN] 预览创建: $PVC_NAME (Size: $PVC_SIZE, SC: $STORAGE_CLASS)"
        fi
    fi
done

# ------------------------------
# 9. 孤儿 PV 深度清理
# ------------------------------
log "=== Step 3: 清理已释放(Released)的孤儿 PV ==="
ORPHAN_PVS=$(kubectl get pv -o json | jq -r ".items[] | select(.status.phase==\"Released\" and .spec.claimRef.namespace==\"$NAMESPACE\") | .metadata.name" || true)
if [[ -n "$ORPHAN_PVS" ]]; then
    for pv in $ORPHAN_PVS; do
        log "🧹 清理残留 PV: $pv"
        exec_cmd "kubectl delete pv $pv"
    done
else
    log "✅ 未发现残留 PV"
fi

# ------------------------------
# 结束统计
# ------------------------------
log "---------------------------------------------------"
log "✅ PostgreSQL HA 资源规范化任务处理完成"
if [[ "$DRY_RUN" == "true" ]]; then
    log "💡 当前为【预览模式】，执行真实操作请运行: DRY_RUN=false bash $0"
fi
log "📄 详细操作日志已存至: $LOG_FILE"
