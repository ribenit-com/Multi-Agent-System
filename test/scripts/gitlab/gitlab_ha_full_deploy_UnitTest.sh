#!/bin/bash
set -e

source ./check_gitlab_names_json.sh

#########################################
# 测试框架（极简）
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

    # UT-01 namespace 不存在
    "get ns ns-mid-storage-prod")
      return 1
      ;;

    # UT-03 service 不存在
    *"get svc gitlab"*)
      return 1
      ;;

    # UT-04 pvc 命名错误
    *"get pvc -o name"*)
      echo "pvc/badname"
      ;;

    # UT-05 pod 非 Running
    *"get pods --no-headers"*)
      echo "gitlab-xxx 1/1 CrashLoopBackOff 3 1m"
      ;;

    *)
      return 0
      ;;
  esac
}

#########################################
# 覆盖 kctl
#########################################
kctl() {
  mock_kctl "$@"
}

#########################################
# UT-01 namespace 不存在 => error
#########################################
json_entries=()
MODE="audit"
check_namespace
result=$(calculate_summary)
assert_equal "error" "$result"

#########################################
# UT-06 汇总逻辑测试
#########################################
json_entries=("warning" "warning")
result=$(calculate_summary)
assert_equal "warning" "$result"

#########################################
# UT-08 全部正常
#########################################
json_entries=()
result=$(calculate_summary)
assert_equal "ok" "$result"

echo "🎉 All tests passed"
