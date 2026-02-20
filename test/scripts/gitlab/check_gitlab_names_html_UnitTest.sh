#!/bin/bash
# ===================================================
# check_gitlab_names_html_UnitTest.sh
# 功能：check_gitlab_names_html.sh 单体测试
# ===================================================

set -e

#########################################
# 1️⃣ 自动下载被测试脚本
#########################################

MODULE="gitlab"
TARGET_SCRIPT="check_${MODULE}_names_html.sh"

if [ ! -f "$TARGET_SCRIPT" ]; then
  echo "⬇️ Downloading target script..."

  curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/GitLab安装包/check_gitlab_names_html.sh \
  -o "$TARGET_SCRIPT"

  chmod +x "$TARGET_SCRIPT"
fi

#########################################
# 2️⃣ 测试环境准备
#########################################

TEST_DIR="./ut_tmp"
OUTPUT_DIR="/mnt/truenas/GitLab安装报告书"

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

#########################################
# 3️⃣ 极简断言函数
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

if ./"$TARGET_SCRIPT" "GitLab_HA" 2>/dev/null; then
  echo "❌ FAIL"
  exit 1
else
  echo "✅ PASS"
fi

#########################################
# 6️⃣ UT-03 JSON 文件不存在
#########################################

if ./"$TARGET_SCRIPT" "GitLab_HA" not_exist.json 2>/dev/null; then
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
  "namespace": "ns-gitlab-ha",
  "statefulset": "sts-gitlab-ha",
  "status": "ok"
}
EOF

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json"

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

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_escape.json"

grep -q "&lt;error &amp; warning&gt;" "$OUTPUT_DIR/latest.html"
assert_equal "0" "$?"

#########################################
# 🔟 UT-07 latest 软链接覆盖
#########################################

FIRST_LINK=$(readlink "$OUTPUT_DIR/latest.html")

sleep 1

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json"

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

OUTPUT=$(./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json")

echo "$OUTPUT" | grep -q "HTML 报告生成完成"
assert_equal "0" "$?"

echo "$OUTPUT" | grep -q "最新报告链接"
assert_equal "0" "$?"

#########################################

echo "🎉 All tests passed"
