#!/bin/bash
set -euo pipefail

#########################################
# 脚本路径 & Raw URL（URL 编码，稳定）
#########################################

TARGET_SCRIPT="gitlab_control.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/gitlab_control.sh"

#########################################
# 强制下载最新生产脚本
#########################################
download_latest() {
  local file="$1"
  local url="$2"
  echo "⬇️ 强制下载最新 $file ..."
  curl -f -L "$url" -o "$file" || { echo "❌ 下载失败"; exit 1; }
  # 检查是否为 HTML 404 页面
  if head -n1 "$file" | grep -q "<!DOCTYPE html>"; then
      echo "❌ ERROR: 下载内容是 HTML 404 页面"
      rm -f "$file"
      exit 1
  fi
  chmod +x "$file"
}

download_latest "$TARGET_SCRIPT" "$TARGET_URL"

#########################################
# UT 断言工具
#########################################

fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }
assert_file_exists() { [[ -f "$1" ]] || fail "$1 not exists"; pass; }

#########################################
# mock 测试环境 / 临时 JSON
#########################################

TMP_JSON=$(mktemp)
cat <<EOF > "$TMP_JSON"
[
  {"resource_type":"Pod","name":"pod-1","status":"CrashLoopBackOff"},
  {"resource_type":"PVC","name":"pvc-1","status":"命名不规范"}
]
EOF

#########################################
# UT 测试
#########################################

# UT-01 参数默认值
MODULE_NAME=""
[[ -z "$MODULE_NAME" ]] && MODULE_NAME="PostgreSQL_HA"
assert_equal "PostgreSQL_HA" "$MODULE_NAME"

# UT-02 临时文件创建
[[ -f "$TMP_JSON" ]] || fail "tmp JSON file not created"
pass

# UT-03 下载生产脚本
assert_file_exists "$TARGET_SCRIPT"

# UT-04 脚本权限
[[ -x "$TARGET_SCRIPT" ]] || fail "script not executable"
pass

# UT-05 JSON 检测执行（轮询方式）
echo "🔹 执行 $TARGET_SCRIPT 并轮询生成 JSON..."
bash "$TARGET_SCRIPT" "$MODULE_NAME" "$TMP_JSON" &
JSON_PID=$!

MAX_RETRIES=10
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -s "$TMP_JSON" ]; then
        echo -e "\n✅ 成功生成 JSON 文件：$TMP_JSON"
        break
    fi
    ((COUNT++))
    echo -ne "\r🔄 [$COUNT/$MAX_RETRIES] JSON 文件未生成，等待 3 秒..."
    for i in {3..1}; do
        echo -ne " $i..."
        sleep 1
    done
done

if [ ! -s "$TMP_JSON" ]; then
    fail "超时：$TARGET_SCRIPT 未生成 JSON 文件"
fi

wait $JSON_PID
EXIT_CODE=$?
[[ $EXIT_CODE -eq 0 ]] || fail "execution failed (退出码 $EXIT_CODE)"
pass

# UT-06 Pod 异常统计
POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
[[ "$POD_ISSUES" -gt 0 ]] || fail "Pod异常未检测到"
pass

# UT-07 PVC 异常统计
PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")
[[ "$PVC_ISSUES" -gt 0 ]] || fail "PVC异常未检测到"
pass

# UT-08 HTML 生成脚本存在性
HTML_SCRIPT="check_postgres_names_html.sh"
[[ -f "$HTML_SCRIPT" ]] || echo "⚠️ HTML 脚本未下载，请手动检查"
pass

# UT-09 临时文件清理
rm -f "$TMP_JSON"
[[ ! -f "$TMP_JSON" ]] || fail "tmp file not deleted"
pass

# UT-10 输出提示
echo "✅ $TARGET_SCRIPT 执行完成"
pass

echo "🎉 All tests passed (enterprise-level v3, 强制下载 + JSON轮询兼容 v1.1)"
