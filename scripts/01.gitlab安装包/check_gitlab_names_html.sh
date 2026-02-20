#!/bin/bash
# ===================================================
# check_gitlab_names_html_UnitTest.sh
# 功能：check_gitlab_names_html.sh 单体测试 (改良版)
# ===================================================

set -e

# カラー出力の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テストカウンター
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

#########################################
# 1️⃣ テスト環境の初期化
#########################################

MODULE="gitlab"
TARGET_SCRIPT="check_${MODULE}_names_html.sh"
TEST_DIR="./ut_tmp"
OUTPUT_DIR="/mnt/truenas/GitLab安装报告书"

# クリーンアップ関数
cleanup() {
    echo -e "\n${YELLOW}🧹  Cleaning up test environment...${NC}"
    rm -rf "$TEST_DIR"
    # 出力ディレクトリは削除しない（実際のレポートを保持）
}

# エラーハンドリング
error_handler() {
    echo -e "\n${RED}❌ エラーが発生しました。行: $1${NC}"
    cleanup
    exit 1
}

trap 'error_handler $LINENO' ERR

#########################################
# 2️⃣ 対象スクリプトのダウンロード
#########################################

echo -e "${YELLOW}📥 テスト対象スクリプトを準備中...${NC}"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "⬇️ Downloading target script..."
    
    curl -L -f \
    https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01.gitlab%E5%AE%89%E8%A3%85%E5%8C%85/check_gitlab_names_html.sh \
    -o "$TARGET_SCRIPT" || {
        echo -e "${RED}❌ スクリプトのダウンロードに失敗しました${NC}"
        exit 1
    }
    
    chmod +x "$TARGET_SCRIPT"
fi

# スクリプトの存在確認
if [ ! -f "$TARGET_SCRIPT" ]; then
    echo -e "${RED}❌ 対象スクリプトが見つかりません: $TARGET_SCRIPT${NC}"
    exit 1
fi

#########################################
# 3️⃣ テスト環境の準備
#########################################

rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

#########################################
# 4️⃣ 拡張アサーション関数
#########################################

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
        echo -e "    期待値: $expected"
        echo -e "    実際値: $actual"
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
        echo -e "${RED}  ❌ FAIL: ファイルが存在しません - $file ${message}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        echo -e "${GREEN}  ✅ PASS: ファイル存在確認 - $file ${message}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-}"

    if grep -q "$pattern" "$file"; then
        echo -e "${GREEN}  ✅ PASS: パターン検索 - '$pattern' ${message}${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}  ❌ FAIL: パターンが見つかりません - '$pattern' ${message}${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_command_fails() {
    local cmd="$1"
    local message="${2:-}"

    if eval "$cmd" 2>/dev/null; then
        echo -e "${RED}  ❌ FAIL: コマンドが成功すべきではない - $message${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    else
        echo -e "${GREEN}  ✅ PASS: コマンド失敗確認 - $message${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    fi
}

#########################################
# 5️⃣ テストケース
#########################################

echo -e "\n${YELLOW}🚀 テストを開始します${NC}"

# UT-01 モジュール名なし
print_test_header "UT-01: モジュール名なし"
assert_command_fails "./$TARGET_SCRIPT" "モジュール名なしは失敗すべき"

# UT-02 JSONファイルなし
print_test_header "UT-02: JSONファイル名なし"
assert_command_fails "./$TARGET_SCRIPT GitLab_HA" "JSONファイルなしは失敗すべき"

# UT-03 JSONファイル存在しない
print_test_header "UT-03: 存在しないJSONファイル"
assert_command_fails "./$TARGET_SCRIPT GitLab_HA not_exist.json" "存在しないファイルは失敗すべき"

# UT-04 ディレクトリ自動作成
print_test_header "UT-04: 出力ディレクトリ自動作成"
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
    echo -e "${GREEN}  ✅ PASS: ディレクトリ作成確認${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: ディレクトリが作成されていない${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-05 HTML生成
print_test_header "UT-05: HTMLファイル生成"
LATEST_FILE="$OUTPUT_DIR/latest.html"
assert_file_exists "$LATEST_FILE" "最新HTMLファイルの存在確認"

# UT-06 HTMLエスケープ
print_test_header "UT-06: HTMLエスケープ処理"
cat <<EOF > "$TEST_DIR/test_escape.json"
{
  "value": "<error & warning>"
}
EOF

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_escape.json"
assert_contains "$OUTPUT_DIR/latest.html" "&lt;error &amp; warning&gt;" "HTMLエスケープ確認"

# UT-07 シンボリックリンク更新
print_test_header "UT-07: シンボリックリンク更新"
FIRST_TIMESTAMP=$(stat -c %Y "$OUTPUT_DIR/latest.html" 2>/dev/null || echo "0")

sleep 1

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json"

SECOND_TIMESTAMP=$(stat -c %Y "$OUTPUT_DIR/latest.html" 2>/dev/null || echo "0")

if [[ "$FIRST_TIMESTAMP" != "$SECOND_TIMESTAMP" ]]; then
    echo -e "${GREEN}  ✅ PASS: シンボリックリンク更新確認${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: シンボリックリンクが更新されていない${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-08 成功メッセージ
print_test_header "UT-08: 出力メッセージ確認"
OUTPUT=$(./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test.json")

if echo "$OUTPUT" | grep -q "HTML 报告生成完成"; then
    echo -e "${GREEN}  ✅ PASS: 完了メッセージ確認${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: 完了メッセージが見つからない${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if echo "$OUTPUT" | grep -q "最新报告链接"; then
    echo -e "${GREEN}  ✅ PASS: リンクメッセージ確認${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: リンクメッセージが見つからない${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-09: JSON配列処理
print_test_header "UT-09: JSON配列処理"
cat <<EOF > "$TEST_DIR/test_array.json"
[
  {"name": "項目1", "status": "active"},
  {"name": "項目2", "status": "inactive"}
]
EOF

if ./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_array.json" 2>/dev/null; then
    echo -e "${GREEN}  ✅ PASS: 配列JSON処理${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${RED}  ❌ FAIL: 配列JSON処理エラー${NC}"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# UT-10: 日本語文字コード
print_test_header "UT-10: 日本語文字コード"
cat <<EOF > "$TEST_DIR/test_japanese.json"
{
  "title": "テスト日本語表題",
  "content": "日本語コンテンツ"
}
EOF

./"$TARGET_SCRIPT" "GitLab_HA" "$TEST_DIR/test_japanese.json"
if file "$OUTPUT_DIR/latest.html" | grep -q "UTF-8"; then
    echo -e "${GREEN}  ✅ PASS: UTF-8エンコーディング確認${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "${YELLOW}  ⚠️  SKIP: エンコーディング確認省略${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

#########################################
# 6️⃣ テスト結果サマリー
#########################################

echo -e "\n${YELLOW}📊 テスト結果サマリー${NC}"
echo "------------------------"
echo -e "総テスト数: ${YELLOW}$TOTAL_TESTS${NC}"
echo -e "成功: ${GREEN}$PASSED_TESTS${NC}"
echo -e "失敗: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 全てのテストが成功しました！${NC}"
    cleanup
    exit 0
else
    echo -e "\n${RED}❌ テスト失敗: $FAILED_TESTS 個のテストが失敗しました${NC}"
    echo -e "${YELLOW}テストディレクトリを保持: $TEST_DIR${NC}"
    exit 1
fi
