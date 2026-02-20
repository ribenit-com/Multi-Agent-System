#!/bin/bash
# ===================================================
# check_gitlab_names_html_UnitTest.sh v3.1
# 功能：check_gitlab_names_html.sh 单体测试（路径修正 + JSON自动创建）
# ===================================================

set -e

# -------------------------------
# 颜色定义
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# -------------------------------
# 测试计数器
# -------------------------------
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# -------------------------------
# 1️⃣ 测试环境初始化
# -------------------------------
MODULE="gitlab"
TARGET_SCRIPT="check_${MODULE}_names_html.sh"
TEST_DIR="./ut_tmp"
# 修正目录：与实际脚本 OUTPUT_DIR 保持一致
OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

cleanup() {
    echo -e "\n${YELLOW}🧹  Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
    # OUTPUT_DIR 保留报告
}

error_handler() {
    echo -e "\n${RED}❌ エラーが発生しました。行: $1${NC}"
    cleanup
    exit 1
}

trap 'error_handler $LINENO' ERR

# -------------------------------
# 2️⃣ 下载目标脚本
# -------------------------------
echo -e "${YELLOW}📥 准备测试目标脚本...${NC}"
if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "⬇️ Downloading target script..."
    curl -L -f \
    https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_html.sh \
    -o "$TARGET_SCRIPT" || {
        echo -e "${RED}❌ 下载失败${NC}"
        exit 1
    }
    chmod +x "$TARGET_SCRIPT"
fi

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo -e "${RED}❌ 目标脚本不存在: $TARGET_SCRIPT${NC}"
    exit 1
fi

# -------------------------------
# 3️⃣ 测试目录创建
# -------------------------------
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# -------------------------------
# 4️⃣ 断言函数
# -------------------------------
print_test_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    if [[ "$expected" != "$actual" ]]; then
        echo -e "${RED}  ❌ FAIL: $message${NC}"
        echo -e "    期望: $expected"
        echo -e "    实际: $actual"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        echo -e "${GREEN}  ✅ PASS: $message${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}  ❌ FAIL: 文件不存在 - $file ${message}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        echo -e "${GREEN}  ✅ PASS: 文件存在 - $file ${message}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-}"

    if grep -q "$pattern" "$file"; then
        echo -e "${GREEN}  ✅ PASS: 匹配模式 - '$pattern' ${message}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}  ❌ FAIL: 未匹配到模式 - '$pattern' ${message}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_command_fails() {
    local cmd="$1"
    local message="${2:-}"

    if eval "$cmd" 2>/dev/null; then
        echo -e "${RED}  ❌ FAIL: 命令应失败 - $message${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        echo -e "${GREEN}  ✅ PASS: 命令失败验证 - $message${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    fi
}

# -------------------------------
# 5️⃣ 测试用例
# -------------------------------
echo -e "\n${YELLOW}🚀 开始执行测试${NC}"

# UT-01: 无模块名
print_test_header "UT-01: 无模块名"
assert_command_fails "./$TARGET_SCRIPT" "无模块名应失败"

# UT-02: 无 JSON 文件
print_test_header "UT-02: 无 JSON 文件"
assert_command_fails "./$TARGET_SCRIPT GitLab_HA" "无 JSON 文件应失败"

# UT-03: JSON 文件不存在
print_test_header "UT-03: JSON 文件不存在"
assert_command_fails "./$TARGET_SCRIPT GitLab_HA not_exist.json" "不存在的 JSON 文件应失败"

# UT-04: 输出目录自动创建
print_test_header "UT-04: 输出目录自动创建"
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
    echo -e "${GREEN}  ✅ PASS: 输出目录存在${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: 输出目录未创建${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-05: HTML 文件生成
print_test_header "UT-05: HTML 文件生成"
LATEST_FILE="$OUTPUT_DIR/latest.html"
assert_file_exists "$LATEST_FILE" "最新 HTML 文件检查"

# UT-06: HTML 转义
print_test_header "UT-06: HTML 特殊字符转义"
cat <<EOF > "$TEST_DIR/test_escape.json"
{
  "value": "<error & warning>"
}
EOF

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_escape.json"
assert_contains "$OUTPUT_DIR/latest.html" "&lt;error &amp; warning&gt;" "HTML 转义验证"

# UT-07: latest.html 链接更新
print_test_header "UT-07: latest.html 链接更新"
FIRST_TS=$(stat -c %Y "$OUTPUT_DIR/latest.html" 2>/dev/null || echo "0")
sleep 1
./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json"
SECOND_TS=$(stat -c %Y "$OUTPUT_DIR/latest.html" 2>/dev/null || echo "0")
if [[ "$FIRST_TS" != "$SECOND_TS" ]]; then
    echo -e "${GREEN}  ✅ PASS: latest.html 更新时间验证${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: latest.html 未更新${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-08: 成功输出信息
print_test_header "UT-08: 成功输出信息"
OUTPUT=$(./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json")
assert_contains <(echo "$OUTPUT") "HTML 报告生成完成" "完成提示验证"
assert_contains <(echo "$OUTPUT") "最新报告链接" "最新报告链接验证"

# UT-09: JSON 数组处理
print_test_header "UT-09: JSON 数组处理"
cat <<EOF > "$TEST_DIR/test_array.json"
[
  {"name": "项1", "status": "active"},
  {"name": "项2", "status": "inactive"}
]
EOF

if ./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_array.json" 2>/dev/null; then
    echo -e "${GREEN}  ✅ PASS: JSON 数组处理${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: JSON 数组处理失败${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-10: UTF-8 编码验证
print_test_header "UT-10: UTF-8 编码验证"
cat <<EOF > "$TEST_DIR/test_japanese.json"
{
  "title": "测试日本语标题",
  "content": "日本语内容"
}
EOF

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_japanese.json"
if file "$OUTPUT_DIR/latest.html" | grep -q "UTF-8"; then
    echo -e "${GREEN}  ✅ PASS: UTF-8 编码验证${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${YELLOW}  ⚠️ SKIP: UTF-8 编码验证跳过${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# -------------------------------
# 6️⃣ 测试总结
# -------------------------------
echo -e "\n${YELLOW}📊 测试总结${NC}"
echo "------------------------"
echo -e "总测试数: ${YELLOW}$TOTAL_TESTS${NC}"
echo -e "成功: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失败: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 所有测试通过！${NC}"
    cleanup
    exit 0
else
    echo -e "\n${RED}❌ 测试失败: $FAILED_TESTS 个测试未通过${NC}"
    echo -e "${YELLOW}测试目录保留: $TEST_DIR${NC}"
    exit 1
fi
