#!/bin/bash
set -e

#########################################
# 下载执行脚本（UnitTest工具，不含生产函数）
#########################################

EXEC_SCRIPT="check_gitlab_names_json_UnitTest.sh"
if [ ! -f "$EXEC_SCRIPT" ]; then
  echo "⬇️ Downloading execution script..."
  curl -f -L \
    https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/check_gitlab_names_json_UnitTest.sh \
    -o "$EXEC_SCRIPT"
  chmod +x "$EXEC_SCRIPT"
fi

#########################################
# 下载生产脚本（被测试函数）
#########################################

TARGET_SCRIPT="check_gitlab_names_json.sh"
if [ ! -f "$TARGET_SCRIPT" ]; then
  echo "⬇️ Downloading target script..."
  curl -f -L \
    https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01.gitlab%E5%AE%89%E8%A3%85%E5%8C%85/check_gitlab_names_json.sh \
    -o "$TARGET_SCRIPT"
  chmod +x "$TARGET_SCRIPT"
fi

#########################################
# 加载生产代码
#########################################

source ./"$TARGET_SCRIPT"

#########################################
# 断言工具
#########################################

fail() {
  echo "❌ FAIL: $1"
  exit 1
}

pass() {
  echo "✅ PASS"
}

assert_equal() {
  expected="$1"
  actual="$2"
  [[ "$expected" == "$actual" ]] || fail "expected=$expected actual=$actual"
  pass
}

assert_array_contains() {
  value="$1"
  shift
  for item in "$@"; do
    [[ "$item" == "$value" ]] && pass && return
  done
  fail "array does not contain $value"
}

assert_array_length() {
  expected="$1"
  shift
  actual="$#"
  [[ "$expected" -eq "$actual" ]] || fail "expected length=$expected actual=$actual"
  pass
}

#########################################
# mock kubectl
#########################################

mock_kctl() {
  case "$*" in
    "get ns ns-mid-storage-prod")
      return 1
      ;;
    *"get svc gitlab"* )
      return 1
      ;;
    *"get pvc -o name"* )
      echo "pvc/badname"
      ;;
    *"get pods --no-headers"* )
      echo "gitlab-xxx 1/1 CrashLoopBackOff 3 1m"
      ;;
    *)
      return 0
      ;;
  esac
}

kctl() {
  mock_kctl "$@"
}

#########################################
# UT-01 namespace audit → error
#########################################

json_entries=()
MODE="audit"
check_namespace

assert_array_length 1 "${json_entries[@]}"
assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

#########################################
# UT-02 namespace enforce → warning
#########################################

json_entries=()
MODE="enforce"
check_namespace

assert_array_length 1 "${json_entries[@]}"
assert_array_contains "warning" "${json_entries[@]}"
assert_equal "warning" "$(calculate_summary)"

#########################################
# UT-03 service 不存在 → error
#########################################

json_entries=()
check_service

assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

#########################################
# UT-04 pvc 命名异常 → warning
#########################################

json_entries=()
check_pvc

assert_array_contains "warning" "${json_entries[@]}"
assert_equal "warning" "$(calculate_summary)"

#########################################
# UT-05 pod CrashLoop → error
#########################################

json_entries=()
check_pod

assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

#########################################
# UT-06 summary 有 error → error
#########################################

json_entries=("error" "warning")
assert_equal "error" "$(calculate_summary)"

#########################################
# UT-07 仅 warning → warning
#########################################

json_entries=("warning" "warning")
assert_equal "warning" "$(calculate_summary)"

#########################################
# UT-08 无异常 → ok
#########################################

json_entries=()
assert_equal "ok" "$(calculate_summary)"

#########################################

echo "🎉 All tests passed (v3 enterprise level)"
