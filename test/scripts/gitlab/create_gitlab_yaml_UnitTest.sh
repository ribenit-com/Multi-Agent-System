#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（生产级 / 固定目录版）
#########################################

EXEC_SCRIPT="./create_gitlab_yaml_UnitTest.sh"
TARGET_SCRIPT="create_gitlab_yaml.sh"

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

VERSION="v1.0.2"   # 单元测试版本

#########################################
# Header 输出
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
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }

#########################################
# 固定输出目录 / 模块名
#########################################
TEST_DIR="/mnt/truenas/Gitlab_yaml_output"
MODULE="gb"   # 新前缀

log "▶️ 检查 YAML 文件目录: $TEST_DIR"

#########################################
# 运行目标脚本生成 YAML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$TARGET_SCRIPT" 2>&1)
echo "$OUTPUT"

#########################################
# UT 测试
#########################################

# Namespace YAML
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# Secret YAML
assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

# StatefulSet YAML
assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# Service YAML
assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# CronJob YAML
assert_file_exists "$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$TEST_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

log "🎉 All YAML generation tests passed (fixed directory / gb prefix)"
