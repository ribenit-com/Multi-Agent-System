#!/bin/bash
set -euo pipefail

#########################################
# 脚本路径 & Raw URL
#########################################

EXEC_SCRIPT="check_gitlab_names_json_UnitTest.sh"
TARGET_SCRIPT="check_gitlab_names_json.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/check_gitlab_names_json_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_json.sh"

#########################################
# 下载脚本（如果不存在）
#########################################

download_if_missing() {
  local file="$1"
  local url="$2"
  if [ ! -f "$file" ]; then
    echo "⬇️ Downloading $file ..."
    curl -f -L "$url" -o "$file"
    chmod +x "$file"
  fi
}

download_if_missing "$EXEC_SCRIPT" "$EXEC_URL"
download_if_missing "$TARGET_SCRIPT" "$TARGET_URL"

#########################################
# 加载生产代码
#########################################

source ./"$TARGET_SCRIPT"

#########################################
# UT 断言工具
#########################################

fail() {
  echo "❌ FAIL: $1"
  exit 1
}

pass() {
  echo "✅ PASS"
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]] || fail "expected=$expected actual=$actual"
  pass
}

assert_array_contains() {
  local value="$1"
  shift
  for item in "$@"; do
    [[ "$item" == "$value" ]] && pass && return
  done
  fail "array does not contain $value"
}

assert_array_length() {
  local expected="$1"
  shift
  local actual="$#"
  [[ "$expected" -eq "$actual" ]] || fail "expected length=$expected actual=$actual"
  pass
}

#########################################
# mock kubectl
#########################################

mock_kctl() {
  case "$*" in
    "get ns ns-mid-storage-prod") return 1 ;;
    *"get svc gitlab"*) return 1 ;;
    *"get pvc -o name"*) echo "pvc/badname" ;;
    *"get pods --no-headers"*) echo "gitlab-xxx 1/1 CrashLoopBackOff 3 1m" ;;
    *) return 0 ;;
  esac
}

kctl() {
  mock_kctl "$@"
}

#########################################
# UT 测试
#########################################

# UT-01 namespace audit → error
json_entries=()
MODE="audit"
check_namespace
assert_array_length 1 "${json_entries[@]}"
assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

# UT-02 namespace enforce → warning
json_entries=()
MODE="enforce"
check_namespace
assert_array_length 1 "${json_entries[@]}"
assert_array_contains "warning" "${json_entries[@]}"
assert_equal "warning" "$(calculate_summary)"

# UT-03 service 不存在 → error
json_entries=()
check_service
assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

# UT-04 pvc 命名异常 → warning
json_entries=()
check_pvc
assert_array_contains "warning" "${json_entries[@]}"
assert_equal "warning" "$(calculate_summary)"

# UT-05 pod CrashLoop → error
json_entries=()
check_pod
assert_array_contains "error" "${json_entries[@]}"
assert_equal "error" "$(calculate_summary)"

# UT-06 summary 有 error → error
json_entries=("error" "warning")
assert_equal "error" "$(calculate_summary)"

# UT-07 仅 warning → warning
json_entries=("warning" "warning")
assert_equal "warning" "$(calculate_summary)"

# UT-08 无异常 → ok
json_entries=()
assert_equal "ok" "$(calculate_summary)"

echo "🎉 All tests passed (enterprise-level v3)"
