#!/bin/bash
set -e

#########################################
# 1️⃣ 自动下载被测试脚本
#########################################

TARGET_SCRIPT="check_gitlab_names_html.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
  echo "⬇️ Downloading target script..."

  curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL安装包/check_postgresql_names_html.sh \
  -o "$TARGET_SCRIPT"

  chmod +x "$TARGET_SCRIPT"
fi

#########################################
# 2️⃣ 测试环境准备
#########################################

TEST_DIR="./ut_tmp"
OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

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

assert_file_exists() {
  if [[ ! -f "$1" ]]; then
    echo "❌ FAIL: file not found $1"
    exit 1
  else
    echo "✅ PASS"
  fi
}

#########################################
# 4️⃣ UT-01 未传入模块名
#########################################

if ./"$TARGET_SCRIPT" 2>/dev/null; then
  echo "❌ FAIL"
  exit 1
else
  echo "✅ PASS"
fi

#########################################
# 5️⃣ UT-02 未传入 JSON 文件
#########################################

if ./"$TARGET_SCRIPT" "PostgreSQL_HA" 2>/dev/null; then
  echo "❌ FAIL"
  exit 1
else
  echo "✅ PASS"
fi

#########################################
# 6️⃣ UT-03 JSON 文件不存在
#########################################

if ./"$TARGET_SCRIPT" "PostgreSQL_HA" not_exist.json 2>/dev/null; then
  echo "❌ FAIL"
  exit 1
else
  echo "✅ PASS"
fi

#########################################
# 7️⃣ UT-04 目录自动创建
#########################################

rm -rf "$OUTPUT_DIR"

cat <<EOF > "$TEST_DIR/test.json"
{
  "status": "ok"
}
EOF

./"$TARGET_SCRIPT" "PostgreSQL_HA" "$TEST_DIR/test.json"

if [[ -d "$OUTPUT_DIR" ]]; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
  exit 1
fi

#########################################
# 8️⃣ UT-05 HTML 正常生成
#########################################

LATEST_FILE="$OUTPUT_DIR/latest.html"
assert_file_exists "$LATEST_FILE"

#########################################
# 9️⃣ UT-06 HTML 转义测试
#########################################

cat <<EOF > "$TEST_DIR/test_escape.json"
{
  "value": "<error & warning>"
}
EOF

./"$TARGET_SCRIPT" "PostgreSQL_HA" "$TEST_DIR/test_escape.json"

grep -q "&lt;error &amp; warning&gt;" "$OUTPUT_DIR/latest.html"
assert_equal "0" "$?"

#########################################
# 🔟 UT-07 latest 软链接覆盖
#########################################

FIRST_LINK=$(readlink "$OUTPUT_DIR/latest.html")

sleep 1

./"$TARGET_SCRIPT" "PostgreSQL_HA" "$TEST_DIR/test.json"

SECOND_LINK=$(readlink "$OUTPUT_DIR/latest.html")

if [[ "$FIRST_LINK" != "$SECOND_LINK" ]]; then
  echo "✅ PASS"
else
  echo "❌ FAIL"
  exit 1
fi

#########################################
# 1️⃣1️⃣ UT-08 成功输出信息
#########################################

OUTPUT=$(./"$TARGET_SCRIPT" "PostgreSQL_HA" "$TEST_DIR/test.json")

echo "$OUTPUT" | grep -q "HTML 报告生成完成"
assert_equal "0" "$?"

echo "$OUTPUT" | grep -q "最新报告链接"
assert_equal "0" "$?"

#########################################

echo "🎉 All tests passed"
