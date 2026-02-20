#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（生产级，固定目录）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen.sh"  # 目标脚本就是 create_gitlab_yaml.sh
YAML_DIR="/mnt/truenas/Gitlab_yaml_output"
OUTPUT_DIR="/mnt/truenas/Gitlab_output"
VERSION="v1.0.2"

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
# 检查 YAML 文件
#########################################
log "▶️ 检查 YAML 文件目录: $YAML_DIR"

PREFIX="gb"

# UT-01 Namespace YAML
assert_file_exists "$YAML_DIR/${PREFIX}_namespace.yaml"
assert_file_contains "$YAML_DIR/${PREFIX}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$YAML_DIR/${PREFIX}_namespace.yaml" "name: ns-test-gitlab"

# UT-02 Secret YAML
assert_file_exists "$YAML_DIR/${PREFIX}_secret.yaml"
assert_file_contains "$YAML_DIR/${PREFIX}_secret.yaml" "root-password"

# UT-03 StatefulSet YAML
assert_file_exists "$YAML_DIR/${PREFIX}_statefulset.yaml"
assert_file_contains "$YAML_DIR/${PREFIX}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$YAML_DIR/${PREFIX}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# UT-04 Service YAML
assert_file_exists "$YAML_DIR/${PREFIX}_service.yaml"
assert_file_contains "$YAML_DIR/${PREFIX}_service.yaml" "nodePort: 30080"
assert_file_contains "$YAML_DIR/${PREFIX}_service.yaml" "nodePort: 30022"
assert_file_contains "$YAML_DIR/${PREFIX}_service.yaml" "nodePort: 35050"

# UT-05 CronJob YAML
assert_file_exists "$YAML_DIR/${PREFIX}_cronjob.yaml"
assert_file_contains "$YAML_DIR/${PREFIX}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$YAML_DIR/${PREFIX}_cronjob.yaml" "persistentVolumeClaim"

# UT-06 JSON 文件
assert_file_exists "$YAML_DIR/yaml_list.json"
assert_file_contains "$YAML_DIR/yaml_list.json" "${PREFIX}_namespace.yaml"
assert_file_contains "$YAML_DIR/yaml_list.json" "${PREFIX}_secret.yaml"

# UT-07 HTML 文件
HTML_FILE="$OUTPUT_DIR/postgres_ha_info.html"
assert_file_exists "$HTML_FILE"
assert_file_contains "$HTML_FILE" "<html>"

log "🎉 All YAML generation tests passed (fixed directories v1)"
