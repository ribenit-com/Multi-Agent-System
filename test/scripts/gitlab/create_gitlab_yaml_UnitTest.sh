#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 单元测试（临时目录版）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen.sh"
EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"
VERSION="v1.0.2"

#########################################
# Header 输出
#########################################
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

log "======================================"
log "📌 单元测试脚本: ./create_gitlab_yaml_UnitTest.sh"
log "📌 目标脚本: $EXEC_SCRIPT"
log "📌 版本: $VERSION"
log "======================================"

#########################################
# 强制下载最新目标脚本
#########################################
download_latest() {
    local file="$1"
    local url="$2"
    log "⬇️ 下载最新脚本: $url"
    curl -fsSL "$url" -o "$file" || { log "❌ 下载失败: $url"; exit 1; }
    chmod +x "$file"
    log "✅ 下载完成: $file"
}

download_latest "$EXEC_SCRIPT" "$EXEC_URL"

#########################################
# UT 断言工具
#########################################
fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() { grep -q "$2" "$1" || fail "File $1 does not contain '$2'"; pass; }

#########################################
# 测试环境准备（临时目录）
#########################################
BASE_DIR=$(mktemp -d)
YAML_DIR="$BASE_DIR/yaml"
OUTPUT_DIR="$BASE_DIR/output"
mkdir -p "$YAML_DIR" "$OUTPUT_DIR"
log "📂 临时测试目录: $BASE_DIR"

#########################################
# 执行目标脚本生成 YAML/JSON/HTML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$EXEC_SCRIPT" 2>&1)
echo "$OUTPUT"

#########################################
# UT 测试
#########################################
for f in namespace secret statefulset service cronjob; do
    YAML_FILE="$YAML_DIR/gb_${f}.yaml"
    assert_file_exists "$YAML_FILE"
done

# 简单检查内容
assert_file_contains "$YAML_DIR/gb_namespace.yaml" "apiVersion: v1"
assert_file_contains "$YAML_DIR/gb_secret.yaml" "root-password"
assert_file_contains "$YAML_DIR/gb_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"
assert_file_contains "$YAML_DIR/gb_service.yaml" "nodePort"
assert_file_contains "$YAML_DIR/gb_cronjob.yaml" "registry-garbage-collect"

# JSON 文件存在性
assert_file_exists "$YAML_DIR/yaml_list.json"

# HTML 文件存在性
assert_file_exists "$OUTPUT_DIR/postgres_ha_info.html"

log "🎉 All YAML generation tests passed (temporary directory version)"
log "📂 YAML 目录: $YAML_DIR"
log "📂 输出目录: $OUTPUT_DIR"
