#!/bin/bash
set -e

#########################################
# 1️⃣ 自动下载被测试脚本
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
# 2️⃣ 加载生产代码
#########################################

source ./"$TARGET_SCRIPT"

#########################################
# 3️⃣ 极简断言
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
# 4️⃣ mock kubectl
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

kctl() {
  mock_kctl "$@"
}

#########################################
# 5️⃣ UT-01 ~ UT-08
#########################################

# UT-01 audit 模式 namespace 不存在 → error
json_entries=()
MODE="audit"
check_namespace
assert_equal "error" "$(calculate_summary)"

# UT-02 enforce 模式 namespace 不存在 → warning
json_entries=()
MODE="enforce"
check_namespace
assert_equal "warning" "$(calculate_summary)"

# UT-03 service 不存在 → error
json_entries=()
check_service
assert_equal "error" "$(calculate_summary)"

# UT-04 pvc 命名异常 → warning
json_entries=()
check_pvc
assert_equal "warning" "$(calculate_summary)"

# UT-05 pod CrashLoop → error
json_entries=()
check_pod
assert_equal "error" "$(calculate_summary)"

# UT-06 error + warning → error
json_entries=("error" "warning")
assert_equal "error" "$(calculate_summary)"

# UT-07 全 warning → warning
json_entries=("warning" "warning")
assert_equal "warning" "$(calculate_summary)"

# UT-08 无问题 → ok
json_entries=()
assert_equal "ok" "$(calculate_summary)"

echo "🎉 All tests passed"
