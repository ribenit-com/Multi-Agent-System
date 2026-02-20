#!/bin/bash
# ===================================================
# HeliosGuard
# PostgreSQL HA 合规验证 + 自动修复引擎
# 版本: v4.0
# 类型: 企业级 DevOps Self-Healing Engine
#
# 核心职责:
#   - 命名规范校验
#   - 资源存在性校验
#   - 资源健康状态校验
#   - 合规分级输出
#   - enforce 模式下自动修复
#
# 不负责:
#   - 业务部署逻辑
#   - Helm 安装逻辑
#   - 配置生成逻辑
#
# ===================================================

set -euo pipefail

# ===================================================
# 1️⃣ 运行模式定义
# ===================================================
# ENVIRONMENT:
#   prod / dev / test
#
# MODE:
#   audit   → 只检测，不修改资源
#   enforce → 自动修复可修复问题
# ===================================================

ENVIRONMENT="${1:-prod}"
MODE="${2:-audit}"

# ===================================================
# 2️⃣ 命名规范定义（企业级 GitLab 规则）
# ===================================================
# 命名结构:
# <层级>-<系统>-<角色>[-<环境>]
# 全小写，使用 "-"
# ===================================================

NAMESPACE_STANDARD="ns-mid-storage-${ENVIRONMENT}"
STATEFULSET_STANDARD="sts-postgres-ha"
SERVICE_PRIMARY_STANDARD="svc-postgres-primary"
SERVICE_REPLICA_STANDARD="svc-postgres-replica"
PVC_PREFIX_STANDARD="pvc-postgres-ha-"
APP_NAME="PostgreSQL-HA"

# ===================================================
# 3️⃣ JSON 结果收集器
# ===================================================
# 输出结构:
# {
#   summary:{},
#   details:[]
# }
# ===================================================

json_entries=()

add_entry() {
  local type="$1"
  local name="$2"
  local status="$3"
  local severity="$4"
  local category="$5"
  local action="$6"

  json_entries+=("{\"resource_type\":\"$type\",\"name\":\"$name\",\"status\":\"$status\",\"severity\":\"$severity\",\"category\":\"$category\",\"action\":\"$action\",\"app\":\"$APP_NAME\"}")
}

# ===================================================
# 4️⃣ Namespace 层验证
# ===================================================
# 验证目标:
#   - Namespace 是否存在
#   - 是否符合命名规范
#
# 违规等级:
#   missing → error
# enforce 模式:
#   自动创建 Namespace
# ===================================================

if ! kubectl get ns "$NAMESPACE_STANDARD" >/dev/null 2>&1; then
  if [[ "$MODE" == "enforce" ]]; then
    kubectl create ns "$NAMESPACE_STANDARD"
    add_entry "Namespace" "$NAMESPACE_STANDARD" "已自动创建" "warning" "missing" "created"
  else
    add_entry "Namespace" "$NAMESPACE_STANDARD" "不存在" "error" "missing" "none"
  fi
fi

# 若 Namespace 不存在（audit 模式），终止深入检测
if ! kubectl get ns "$NAMESPACE_STANDARD" >/dev/null 2>&1; then
  SUMMARY_STATUS="error"
else

  # ===================================================
  # 5️⃣ Service 层验证
  # ===================================================
  # 验证目标:
  #   - Primary Service 是否存在
  #   - Replica Service 是否存在
  #
  # 违规等级:
  #   missing → error
  #
  # enforce 模式:
  #   自动创建 ClusterIP Service
  # ===================================================

  for svc in "$SERVICE_PRIMARY_STANDARD" "$SERVICE_REPLICA_STANDARD"; do
    if ! kubectl -n "$NAMESPACE_STANDARD" get svc "$svc" >/dev/null 2>&1; then
      if [[ "$MODE" == "enforce" ]]; then
        kubectl -n "$NAMESPACE_STANDARD" create svc clusterip "$svc" --tcp=5432:5432
        add_entry "Service" "$svc" "已自动创建" "warning" "missing" "created"
      else
        add_entry "Service" "$svc" "不存在" "error" "missing" "none"
      fi
    fi
  done

  # ===================================================
  # 6️⃣ PVC 存储层验证
  # ===================================================
  # 验证目标:
  #   - PVC 是否存在
  #   - 是否符合命名规则
  #
  # 命名正则:
  #   ^pvc-postgres-ha-[0-9]+$
  #
  # 违规等级:
  #   naming → warning
  #
  # enforce 模式:
  #   删除命名错误 PVC（风险操作）
  # ===================================================

  PVC_LIST=$(kubectl -n "$NAMESPACE_STANDARD" get pvc \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

  for pvc in $PVC_LIST; do
    if [[ ! "$pvc" =~ ^${PVC_PREFIX_STANDARD}[0-9]+$ ]]; then
      if [[ "$MODE" == "enforce" ]]; then
        kubectl -n "$NAMESPACE_STANDARD" delete pvc "$pvc"
        add_entry "PVC" "$pvc" "命名错误已删除" "warning" "naming" "deleted"
      else
        add_entry "PVC" "$pvc" "命名不符合规范" "warning" "naming" "none"
      fi
    fi
  done

  # ===================================================
  # 7️⃣ Pod 运行层健康验证
  # ===================================================
  # 验证目标:
  #   - 所有 Pod 状态必须为 Running
  #
  # 异常状态:
  #   Pending
  #   CrashLoopBackOff
  #   Error
  #   Terminating
  #
  # 违规等级:
  #   unhealthy → error
  #
  # enforce 模式:
  #   删除异常 Pod 触发自动重建
  # ===================================================

  POD_STATUS=$(kubectl -n "$NAMESPACE_STANDARD" get pods \
    -o custom-columns=NAME:.metadata.name,STATUS:.status.phase \
    --no-headers 2>/dev/null || true)

  while read -r line; do
    POD_NAME=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $2}')
    if [[ "$STATUS" != "Running" ]]; then
      if [[ "$MODE" == "enforce" ]]; then
        kubectl -n "$NAMESPACE_STANDARD" delete pod "$POD_NAME"
        add_entry "Pod" "$POD_NAME" "异常已重建" "warning" "unhealthy" "restarted"
      else
        add_entry "Pod" "$POD_NAME" "$STATUS" "error" "unhealthy" "none"
      fi
    fi
  done <<< "$POD_STATUS"

fi

# ===================================================
# 8️⃣ 合规等级计算逻辑
# ===================================================
# 规则:
#   error_count > 0  → status = error
#   warning_count > 0 → status = warning
#   否则 → ok
# ===================================================

ERROR_COUNT=$(printf "%s\n" "${json_entries[@]}" | grep -c '"severity":"error"' || true)
WARNING_COUNT=$(printf "%s\n" "${json_entries[@]}" | grep -c '"severity":"warning"' || true)

if [[ "$ERROR_COUNT" -gt 0 ]]; then
  SUMMARY_STATUS="error"
elif [[ "$WARNING_COUNT" -gt 0 ]]; then
  SUMMARY_STATUS="warning"
else
  SUMMARY_STATUS="ok"
fi

# ===================================================
# 9️⃣ JSON 标准输出
# ===================================================

if [ ${#json_entries[@]} -eq 0 ]; then
  echo "{\"summary\":{\"status\":\"ok\",\"mode\":\"$MODE\",\"error_count\":0,\"warning_count\":0},\"details\":[]}"
else
  printf "{\n"
  printf "\"summary\":{\"status\":\"%s\",\"mode\":\"%s\",\"error_count\":%s,\"warning_count\":%s},\n" \
    "$SUMMARY_STATUS" "$MODE" "$ERROR_COUNT" "$WARNING_COUNT"
  printf "\"details\":[\n%s\n]\n" "$(IFS=,; echo "${json_entries[*]}")"
  printf "}\n"
fi

# ===================================================
# HeliosGuard 结束
# ===================================================
