#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（增强版，生产级日志追踪）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="gitlab_yaml_gen.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

VERSION="v1.0.1"   # 版本号手动维护

#########################################
# 日志函数
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

log "======================================"
log "📌 单元测试脚本: $EXEC_SCRIPT"
log "📌 目标脚本: $TARGET_SCRIPT"
log "📌 版本: $VERSION"
log "======================================"

#########################################
# 下载脚本
#########################################
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

#########################################
# UT 辅助函数
#########################################
fail() {
    echo "❌ FAIL: $1"
    exit 1
}
pass() { echo "✅ PASS"; }

assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() {
    local file="$1"
    local text="$2"
    if grep -qF "$text" "$file"; then
        pass
    else
        echo "❌ File $file does not contain expected text: '$text'"
        echo "---- 文件最后10行 ----"
        tail -n 10 "$file"
        echo "---------------------"
        fail "assert_file_contains failed"
    fi
}
assert_output_contains() {
    local output="$1"
    local expected="$2"
    if echo "$output" | grep -qF "$expected"; then
        pass
    else
        echo "❌ Output does not contain expected text: '$expected'"
        echo "---- 输出最后20行 ----"
        echo "$output" | tail -n 20
        echo "---------------------"
        fail "assert_output_contains failed"
    fi
}

#########################################
# 测试环境
#########################################
TEST_DIR=$(mktemp -d)
MODULE="GitLab_Test"
export HOME="$TEST_DIR"
log "📂 测试临时目录: $TEST_DIR"

#########################################
# 生成 YAML 并捕获完整输出
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" "ns-test-gitlab" "sc-fast" "50Gi" "gitlab/gitlab-ce:15.0" "gitlab.test.local" "192.168.50.10" "35050" "30022" "30080" 2>&1)
echo "$OUTPUT"

#########################################
# UT 测试
#########################################

# Namespace
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# Secret
assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

# StatefulSet
assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# Service
assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# CronJob
assert_file_exists "$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

# YAML 格式验证
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_namespace.yaml" >/dev/null 2>&1 && pass || fail "Namespace YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_secret.yaml" >/dev/null 2>&1 && pass || fail "Secret YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_statefulset.yaml" >/dev/null 2>&1 && pass || fail "StatefulSet YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_service.yaml" >/dev/null 2>&1 && pass || fail "Service YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_cronjob.yaml" >/dev/null 2>&1 && pass || fail "CronJob YAML invalid"

# 检查输出核心文本
EXPECTED_OUTPUT="GitLab YAML 已生成到 $TEST_DIR"
assert_output_contains "$OUTPUT" "$EXPECTED_OUTPUT"

log "🎉 All YAML generation tests passed (enterprise-level v1)"
