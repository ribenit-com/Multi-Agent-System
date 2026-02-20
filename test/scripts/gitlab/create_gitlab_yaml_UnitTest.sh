#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 单元测试（固定输出目录版）
#########################################

EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="create_gitlab_yaml.sh"  # 指向正确的脚本

EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"

VERSION="v1.0.1"   # 单元测试版本，可手动维护

# 固定输出目录（和目标脚本保持一致）
LOG_DIR="/mnt/truenas/Gitlab_yaml_output"
MODULE="GitLab_Test"

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
log "📌 输出目录: $LOG_DIR"
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
# 运行目标脚本生成 YAML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
OUTPUT=$(bash "$TARGET_SCRIPT" 2>&1)
echo "$OUTPUT"  # 打印完整日志以便追踪

#########################################
# UT 测试（固定目录版）
#########################################

# UT-04 Namespace YAML
assert_file_exists "$LOG_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$LOG_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$LOG_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

# UT-05 Secret YAML
assert_file_exists "$LOG_DIR/${MODULE}_secret.yaml"
assert_file_contains "$LOG_DIR/${MODULE}_secret.yaml" "root-password"

# UT-06 StatefulSet YAML
assert_file_exists "$LOG_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$LOG_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$LOG_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

# UT-07 Service YAML
assert_file_exists "$LOG_DIR/${MODULE}_service.yaml"
assert_file_contains "$LOG_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$LOG_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$LOG_DIR/${MODULE}_service.yaml" "nodePort: 35050"

# UT-08 CronJob YAML
assert_file_exists "$LOG_DIR/${MODULE}_cronjob.yaml"
assert_file_contains "$LOG_DIR/${MODULE}_cronjob.yaml" "registry-garbage-collect"
assert_file_contains "$LOG_DIR/${MODULE}_cronjob.yaml" "persistentVolumeClaim"

# UT-09 YAML 格式验证（kubectl dry-run）
kubectl apply --dry-run=client -f "$LOG_DIR/${MODULE}_namespace.yaml" >/dev/null 2>&1 && pass || fail "Namespace YAML invalid"
kubectl apply --dry-run=client -f "$LOG_DIR/${MODULE}_secret.yaml" >/dev/null 2>&1 && pass || fail "Secret YAML invalid"
kubectl apply --dry-run=client -f "$LOG_DIR/${MODULE}_statefulset.yaml" >/dev/null 2>&1 && pass || fail "StatefulSet YAML invalid"
kubectl apply --dry-run=client -f "$LOG_DIR/${MODULE}_service.yaml" >/dev/null 2>&1 && pass || fail "Service YAML invalid"
kubectl apply --dry-run=client -f "$LOG_DIR/${MODULE}_cronjob.yaml" >/dev/null 2>&1 && pass || fail "CronJob YAML invalid"

# UT-10 输出提示（只匹配核心文本）
EXPECTED_TEXT="✅ YAML / JSON / HTML 已生成在 $LOG_DIR"
echo "$OUTPUT" | grep -q "$EXPECTED_TEXT" && pass || { 
    fail "Output missing expected text"
    echo "🔹 最近日志内容（用于调试）:"
    echo "$OUTPUT" | tail -n 20
}

log "🎉 All YAML generation tests passed (enterprise-level v1)"
