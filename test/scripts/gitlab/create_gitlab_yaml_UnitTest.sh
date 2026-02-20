#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（增强版）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="gitlab_yaml_gen.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

VERSION="v1.0.1"

log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

log "======================================"
log "📌 单元测试脚本: $EXEC_SCRIPT"
log "📌 目标脚本: $TARGET_SCRIPT"
log "📌 版本: $VERSION"
log "======================================"

download_latest() {
    local file="$1"
    local url="$2"
    log "⬇️ 强制下载最新脚本: $url"
    curl -fsSL "$url" -o "$file" || { log "❌ 下载失败: $url"; exit 1; }
    chmod +x "$file"
    log "✅ 下载完成并已赋予执行权限: $file"
}

download_latest "$EXEC_SCRIPT" "$EXEC_URL"
download_latest "$TARGET_SCRIPT" "$TARGET_URL"

fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() { grep -q "$2" "$1" || fail "File $1 does not contain '$2'"; pass; }

#########################################
# 测试环境准备
#########################################
TEST_DIR=$(mktemp -d)
MODULE="GitLab_Test"
export HOME="$TEST_DIR"
log "📂 测试临时目录: $TEST_DIR"

#########################################
# 运行目标脚本生成 YAML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" "ns-test-gitlab" "sc-fast" "50Gi" "gitlab/gitlab-ce:15.0" "gitlab.test.local" "192.168.50.10" "35050" "30022" "30080")

#########################################
# UT 测试
#########################################

# 文件存在与内容检查
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"

assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"

assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"

assert_file_exists "$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"

# 🔹 核心改动：输出匹配，忽略前缀时间戳
EXPECTED_TEXT="GitLab YAML 已生成到 $TEST_DIR"
echo "$OUTPUT" | grep -q "$EXPECTED_TEXT" && pass || {
    echo "❌ Output missing expected text"
    echo "---- 输出最后20行 ----"
    echo "$OUTPUT" | tail -n 20
    echo "----------------------"
    fail "assert_output_contains failed"
}

log "🎉 All YAML generation tests passed (enterprise-level v1)"
