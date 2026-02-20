#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（生产级增强版）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="gitlab_yaml_gen.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

VERSION="v1.0.1"   # 手动维护

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
# 强制下载最新脚本
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
# UT 断言工具
#########################################
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
# 执行目标脚本生成 YAML（捕获输出，完整追踪）
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" "ns-test-gitlab" "sc-fast" "50Gi" "gitlab/gitlab-ce:15.0" "gitlab.test.local" "192.168.50.10" "35050" "30022" "30080" 2>&1)
log "📌 脚本输出开始 =========================="
echo "$OUTPUT"
log "📌 脚本输出结束 =========================="

#########################################
# UT 测试
#########################################

# UT-04 Namespace YAML
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# UT-05 Secret YAML
assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

# UT-06 StatefulSet YAML
assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# UT-07 Service YAML
assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# UT-08 CronJob YAML
assert_file_exists "$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

# UT-09 YAML 格式验证（kubectl dry-run）
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_namespace.yaml" >/dev/null 2>&1 && pass || fail "Namespace YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_secret.yaml" >/dev/null 2>&1 && pass || fail "Secret YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_statefulset.yaml" >/dev/null 2>&1 && pass || fail "StatefulSet YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_service.yaml" >/dev/null 2>&1 && pass || fail "Service YAML invalid"
kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_cronjob.yaml" >/dev/null 2>&1 && pass || fail "CronJob YAML invalid"

# UT-10 输出文本检查（带追踪）
EXPECTED_OUTPUT="✅ GitLab YAML 已生成到 $TEST_DIR"
if echo "$OUTPUT" | grep -qF "$EXPECTED_OUTPUT"; then
    pass
else
    fail "Output missing expected text. Expected: '$EXPECTED_OUTPUT'"
fi

log "🎉 所有 YAML 生成测试完成（增强追踪）"
