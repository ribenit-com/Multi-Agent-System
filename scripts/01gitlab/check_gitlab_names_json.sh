#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-prod}"
MODE="${2:-audit}"

# JSON 条目数组
json_entries=()

#######################################
# kubectl 抽象层
#######################################
kctl() {
  kubectl "$@"
}

#######################################
# 添加 JSON 条目
#######################################
add_entry() {
  json_entries+=("$1")
}

#######################################
# 检查 Namespace
#######################################
check_namespace() {
  ns="ns-mid-storage-$ENVIRONMENT"
  if kctl get ns "$ns" >/dev/null 2>&1; then
    add_entry "{\"resource_type\":\"Namespace\",\"name\":\"$ns\",\"status\":\"存在\"}"
  else
    status=$([[ "$MODE" == "enforce" ]] && echo "警告" || echo "不存在")
    add_entry "{\"resource_type\":\"Namespace\",\"name\":\"$ns\",\"status\":\"$status\"}"
  fi
}

#######################################
# 检查 Service
#######################################
check_service() {
  svc="gitlab"
  if kctl -n "ns-mid-storage-$ENVIRONMENT" get svc "$svc" >/dev/null 2>&1; then
    add_entry "{\"resource_type\":\"Service\",\"name\":\"$svc\",\"status\":\"存在\"}"
  else
    add_entry "{\"resource_type\":\"Service\",\"name\":\"$svc\",\"status\":\"不存在\"}"
  fi
}

#######################################
# 检查 PVC
#######################################
check_pvc() {
  pvc_list=$(kctl -n "ns-mid-storage-$ENVIRONMENT" get pvc -o name 2>/dev/null || true)
  for pvc in $pvc_list; do
    name=$(basename "$pvc")
    if [[ "$name" =~ ^pvc-.*-[0-9]+$ ]]; then
      status="命名规范"
    else
      status="命名不规范"
    fi
    add_entry "{\"resource_type\":\"PVC\",\"name\":\"$name\",\"status\":\"$status\"}"
  done
}

#######################################
# 检查 Pod
#######################################
check_pod() {
  pod_list=$(kctl -n "ns-mid-storage-$ENVIRONMENT" get pods --no-headers 2>/dev/null || true)
  while read -r line; do
    [[ -z "$line" ]] && continue
    name=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $3}')
    add_entry "{\"resource_type\":\"Pod\",\"name\":\"$name\",\"status\":\"$status\"}"
  done <<< "$pod_list"
}

#######################################
# 输出 JSON
#######################################
main() {
  check_namespace
  check_service
  check_pvc
  check_pod

  # 输出数组 JSON
  echo "["
  local first=true
  for entry in "${json_entries[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      echo ","
    fi
    echo -n "$entry"
  done
  echo
  echo "]"
}

#######################################
# 可执行入口
#######################################
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
