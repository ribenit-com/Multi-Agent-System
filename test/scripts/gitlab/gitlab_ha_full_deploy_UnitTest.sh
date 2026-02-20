#!/bin/bash
set -e

source ./check_gitlab_names_json.sh

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

########################################################
# UT-01 namespace 不存在 => error
########################################################
json_entries=()
MODE="audit"
check_namespace
result=$(calculate_summary)
assert_equal "error" "$result"

########################################################
# UT-02 enforce 模式 => warning
########################################################
json_entries=()
MODE="enforce"
check_namespace
result=$(calculate_summary)
assert_equal "warning" "$result"

########################################################
# UT-03 service 不存在 => error
########################################################
json_entries=()
MODE="audit"
check_service
result=$(calculate_summary)
assert_equal "error" "$result"

########################################################
# UT-04 pvc 命名不规范 => warning
########################################################
json_entries=()
check_pvc
result=$(calculate_summary)
assert_equal "warning" "$result"

########################################################
# UT-05 pod 非 Running => error
########################################################
json_entries=()
check_pod
result=$(calculate_summary)
assert_equal "error" "$result"

########################################################
# UT-06 calculate_summary 有 error => error
########################################################
json_entries=("error" "warning")
result=$(calculate_summary)
assert_equal "error" "$result"

########################################################
# UT-07 calculate_summary 仅 warning => warning
########################################################
json_entries=("warning" "warning")
result=$(calculate_summary)
assert_equal "warning" "$result"

########################################################
# UT-08 calculate_summary 无异常 => ok
########################################################
json_entries=()
result=$(calculate_summary)
assert_equal "ok" "$result"

echo "🎉 All tests passed"
