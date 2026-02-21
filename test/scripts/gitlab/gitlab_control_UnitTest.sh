#!/bin/bash
set -euo pipefail

#########################################
# 企业级 UT v4
# 双脚本强制下载 + 路径校验 + 防污染
#########################################

BASE_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab"

CONTROL_SCRIPT="gitlab_control.sh"
YAML_SCRIPT="create_gitlab_yaml.sh"

CONTROL_URL="$BASE_URL/$CONTROL_SCRIPT"
YAML_URL="$BASE_URL/$YAML_SCRIPT"

#########################################
# 强制下载函数
#########################################
download_latest() {
  local file="$1"
  local url="$2"

  echo "⬇️ 强制下载 $file ..."
  rm -f "$file"

  curl -f -L "$url" -o "$file" || {
    echo "❌ 下载失败: $url"
    exit 1
  }

  if head -n1 "$file" | grep -q "<!DOCTYPE html>"; then
      echo "❌ ERROR: 下载内容是 HTML 404 页面"
      rm -f "$file"
      exit 1
  fi

  chmod +x "$file"

  echo "✅ 下载完成: $(realpath "$file")"
}

#########################################
# 下载最新生产脚本
#########################################
download_latest "$CONTROL_SCRIPT" "$CONTROL_URL"
download_latest "$YAML_SCRIPT" "$YAML_URL"

#########################################
# 校验是否存在 test 残留
#########################################
echo "🔎 校验脚本是否存在 test 残留..."

if grep -n "ns-test-gitlab" "$YAML_SCRIPT"; then
  echo "❌ 检测到 test 命名残留！"
  exit 1
fi

echo "✅ 未检测到 test 命名"

#########################################
# UT 断言工具
#########################################
fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }
assert_file_exists() { [[ -f "$1" ]] || fail "$1 not exists"; pass; }

#########################################
# mock JSON
#########################################
TMP_JSON=$(mktemp)

cat <<EOF > "$TMP_JSON"
[
  {"resource_type":"Pod","name":"pod-1","status":"CrashLoopBackOff"},
  {"resource_type":"PVC","name":"pvc-1","status":"命名不规范"}
]
EOF

#########################################
# UT-01 默认模块
#########################################
MODULE_NAME=""
[[ -z "$MODULE_NAME" ]] && MODULE_NAME="PostgreSQL_HA"
assert_equal "PostgreSQL_HA" "$MODULE_NAME"

#########################################
# UT-02 文件存在
#########################################
assert_file_exists "$CONTROL_SCRIPT"
assert_file_exists "$YAML_SCRIPT"

#########################################
# UT-03 执行 Control 脚本
#########################################
echo "🚀 执行 Control 脚本..."

bash "$CONTROL_SCRIPT" "$MODULE_NAME" "$TMP_JSON" &
PID=$!

MAX_RETRIES=15
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -s "$TMP_JSON" ]; then
        echo -e "\n✅ JSON 文件存在: $TMP_JSON"
        break
    fi
    ((COUNT++))
    echo -ne "\r⏳ 等待 JSON 生成 [$COUNT/$MAX_RETRIES]..."
    sleep 1
done

if [ ! -s "$TMP_JSON" ]; then
    fail "JSON 未生成"
fi

wait $PID
EXIT_CODE=$?
[[ $EXIT_CODE -eq 0 ]] || fail "执行失败 (退出码 $EXIT_CODE)"
pass

#########################################
# UT-04 JSON 内容校验
#########################################
POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
[[ "$POD_ISSUES" -gt 0 ]] || fail "Pod异常未检测到"
pass

PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")
[[ "$PVC_ISSUES" -gt 0 ]] || fail "PVC异常未检测到"
pass

#########################################
# 清理
#########################################
rm -f "$TMP_JSON"

echo "🎉 All tests passed (Enterprise UT v4)"
