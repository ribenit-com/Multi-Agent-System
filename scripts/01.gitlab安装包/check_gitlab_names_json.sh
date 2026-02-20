#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-prod}"
MODE="${2:-audit}"

json_entries=()

#######################################
# kubectl 抽象层（可被单测替换）
#######################################
kctl() {
  kubectl "$@"
}

#######################################
# 工具函数
#######################################
add_entry() {
  json_entries+=("$1")
}

#######################################
# 检查函数
#######################################

check_namespace() {
  if ! kctl get ns "ns-mid-storage-$ENVIRONMENT" >/dev/null 2>&1; then
    if [[ "$MODE" == "enforce" ]]; then
      add_entry "warning"
    else
      add_entry "error"
    fi
  fi
}

check_service() {
  if ! kctl -n "ns-mid-storage-$ENVIRONMENT" get svc gitlab >/dev/null 2>&1; then
    add_entry "error"
  fi
}

check_pvc() {
  pvc_list=$(kctl -n "ns-mid-storage-$ENVIRONMENT" get pvc -o name 2>/dev/null || true)

  for pvc in $pvc_list; do
    name=$(basename "$pvc")
    if [[ ! "$name" =~ ^pvc-.*-[0-9]+$ ]]; then
      add_entry "warning"
    fi
  done
}

check_pod() {
  pod_list=$(kctl -n "ns-mid-storage-$ENVIRONMENT" get pods --no-headers 2>/dev/null || true)

  while read -r line; do
    [[ -z "$line" ]] && continue
    status=$(echo "$line" | awk '{print $3}')
    if [[ "$status" != "Running" ]]; then
      add_entry "error"
    fi
  done <<< "$pod_list"
}

#######################################
# 汇总函数
#######################################
calculate_summary() {
  error_count=$(printf "%s\n" "${json_entries[@]}" | grep -c "^error$" || true)
  warning_count=$(printf "%s\n" "${json_entries[@]}" | grep -c "^warning$" || true)

  if [[ "$error_count" -gt 0 ]]; then
    echo "error"
  elif [[ "$warning_count" -gt 0 ]]; then
    echo "warning"
  else
    echo "ok"
  fi
}

#######################################
# 主流程
#######################################
main() {
  check_namespace
  check_service
  check_pvc
  check_pod
  calculate_summary
}

#######################################
# 可执行入口隔离
#######################################
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
