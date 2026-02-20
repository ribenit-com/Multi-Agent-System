# GitLab HA 单体测试（内嵌生产逻辑版本）

> 说明：  
> 不再 source 远程脚本。  
> 直接把 `check_gitlab_names_json.sh` 的逻辑内嵌到测试文件中。  
> 单文件即可执行。

---

## 使用方式

```bash
chmod +x gitlab_ha_full_deploy_UnitTest.sh
./gitlab_ha_full_deploy_UnitTest.sh
```

---

## 单文件完整代码

```bash
#!/bin/bash
set -e

#########################################
# 生产逻辑（内嵌版）
#########################################

ENVIRONMENT="prod"
MODE="audit"
json_entries=()

kctl() {
  kubectl "$@"
}

add_entry() {
  json_entries+=("$1")
}

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

#########################################
# 极简断言
#########################################

assert_equal() {
  expected="$1"
  actual="$2"

  if [[ "$expected" != "$actual" ]]; then
    echo "❌ FAIL: expected=$expected actual=$actual"
    exit 1
  else
    echo "✅ PASS"
  fi
}

#########################################
# mock kubectl
#########################################

mock_kctl() {
  case "$*" in
    "get ns ns-mid-storage-prod")
      return 1
      ;;
    *"get svc gitlab"*)
      return 1
      ;;
    *"get pvc -o name"*)
      echo "pvc/badname"
      ;;
    *"get pods --no-headers"*)
      echo "gitlab-xxx 1/1 CrashLoopBackOff 3 1m"
      ;;
    *)
      return 0
      ;;
  esac
}

# 覆盖 kctl
kctl() {
  mock_kctl "$@"
}

#########################################
# UT-01 ~ UT-08
#########################################

json_entries=()
MODE="audit"
check_namespace
assert_equal "error" "$(calculate_summary)"

json_entries=()
MODE="enforce"
check_namespace
assert_equal "warning" "$(calculate_summary)"

json_entries=()
check_service
assert_equal "error" "$(calculate_summary)"

json_entries=()
check_pvc
assert_equal "warning" "$(calculate_summary)"

json_entries=()
check_pod
assert_equal "error" "$(calculate_summary)"

json_entries=("error" "warning")
assert_equal "error" "$(calculate_summary)"

json_entries=("warning" "warning")
assert_equal "warning" "$(calculate_summary)"

json_entries=()
assert_equal "ok" "$(calculate_summary)"

echo "🎉 All tests passed"
```
