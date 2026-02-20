#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 单元测试（固定目录版）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen.sh"
VERSION="v1.0.3"   # 单元测试版本

#########################################
# 固定目录配置
#########################################
YAML_DIR="/mnt/truenas/Gitlab_yaml_output"
OUTPUT_DIR="/mnt/truenas/Gitlab_output"

#########################################
# Header 输出
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

log "======================================"
log "📌 单元测试脚本: $0"
log "📌 目标脚本: $EXEC_SCRIPT"
log "📌 版本: $VERSION"
log "======================================"

#########################################
# UT 断言工具
#########################################
fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() { grep -q "$2" "$1" || fail "File $1 does not contain '$2'"; pass; }

#########################################
# 运行目标脚本生成 YAML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
bash "$EXEC_SCRIPT"

log "▶️ 检查 YAML 文件目录: $YAML_DIR"

#########################################
# UT 测试
#########################################

MODULE="gb"

# Namespace YAML
assert_file_exists "$YAML_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$YAML_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$YAML_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# Secret YAML
assert_file_exists "$YAML_DIR/${MODULE}_secret.yaml"
assert_file_contains "$YAML_DIR/${MODULE}_secret.yaml" "root-password"

# StatefulSet YAML
assert_file_exists "$YAML_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$YAML_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$YAML_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# Service YAML
assert_file_exists "$YAML_DIR/${MODULE}_service.yaml"
assert_file_contains "$YAML_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$YAML_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$YAML_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# CronJob YAML
assert_file_exists "$YAML_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$YAML_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$YAML_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

# JSON 文件
assert_file_exists "$YAML_DIR/yaml_list.json"

# HTML 文件
assert_file_exists "$OUTPUT_DIR/postgres_ha_info.html"

log "🎉 All YAML generation tests passed (fixed directory v1)"
