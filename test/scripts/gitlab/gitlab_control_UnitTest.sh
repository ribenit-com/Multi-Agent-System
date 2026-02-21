#!/bin/bash
# =============================================================
# GitLab YAML 生成单测（固定输出目录 + GB 前缀 + 日志追踪）
# =============================================================

set -euo pipefail

#########################################
# 脚本信息
#########################################
EXEC_SCRIPT="gitlab_yaml_gen_UnitTest.sh"
TARGET_SCRIPT="gitlab_yaml_gen.sh"
EXEC_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh"
TARGET_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/create_gitlab_yaml.sh"
VERSION="v1.0.3"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

log "======================================"
log "📌 单元测试脚本: $EXEC_SCRIPT"
log "📌 目标脚本: $TARGET_SCRIPT"
log "📌 版本: $VERSION"
log "======================================"

#########################################
# 下载最新脚本
#########################################
download_latest() {
    local file="$1"
    local url="$2"
    log "⬇️ 下载最新脚本: $url"
    curl -fsSL "$url" -o "$file" || { log "❌ 下载失败: $url"; exit 1; }
    chmod +x "$file"
    log "✅ 下载完成并赋予执行权限: $file"
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
# 固定输出目录
#########################################
MODULE="gb"
YAML_DIR="/mnt/truenas/Gitlab_yaml_test_run"
OUTPUT_DIR="/mnt/truenas/Gitlab_output"

mkdir -p "$YAML_DIR"
mkdir -p "$OUTPUT_DIR"

FULL_LOG="$OUTPUT_DIR/full_script.log"

log "📂 YAML 输出目录: $YAML_DIR"
log "📂 输出目录: $OUTPUT_DIR"
log "📄 全量日志: $FULL_LOG"

# 重定向 stdout/stderr 到日志
exec 3>&1 4>&2
exec 1>>"$FULL_LOG" 2>&1
export PS4='+[$LINENO] '
set -x

#########################################
# 调用目标脚本生成 YAML / JSON / HTML
#########################################
log "▶️ 执行目标脚本生成 YAML..."
bash "$TARGET_SCRIPT" "$MODULE" "$YAML_DIR" "$OUTPUT_DIR"

log "✅ YAML / JSON / HTML 已生成"
log "📄 YAML 文件目录: $YAML_DIR"
log "📄 输出目录: $OUTPUT_DIR"
log "📄 全量日志: $FULL_LOG"

#########################################
# 单测检查 YAML 文件是否生成
#########################################
for f in namespace secret statefulset service cronjob; do
    FILE="$YAML_DIR/${MODULE}_$f.yaml"
    log "🔹 检查 YAML 文件: $FILE"
    assert_file_exists "$FILE"
done

# CronJob 内容打印
CRON_FILE="$YAML_DIR/${MODULE}_cronjob.yaml"
log "📌 CronJob YAML 内容:"
nl -w3 -s" | " "$CRON_FILE"

log "📌 CronJob containers.command 内容:"
grep -A10 "command:" "$CRON_FILE"

assert_file_contains "$CRON_FILE" "registry-garbage-collect"
assert_file_contains "$CRON_FILE" "persistentVolumeClaim"

#########################################
# kubectl dry-run 验证 YAML 格式
#########################################
log "▶️ YAML 格式验证 (kubectl dry-run)..."
for f in namespace secret statefulset service cronjob; do
    kubectl apply --dry-run=client -f "$YAML_DIR/${MODULE}_$f.yaml" >/dev/null 2>&1 && pass || fail "$f YAML invalid"
done

#########################################
# 输出提示验证
#########################################
EXPECTED_OUTPUT="✅ YAML / JSON / HTML 已生成到 $YAML_DIR"
bash "$TARGET_SCRIPT" "$MODULE" "$YAML_DIR" "$OUTPUT_DIR" | grep -q "$EXPECTED_OUTPUT" && pass || fail "Output missing expected text"

log "🎉 所有 YAML 生成测试通过 (GB 前缀 + 固定目录 + v1.0.3)"

# 关闭逐行跟踪，恢复 stdout/stderr
set +x
exec 1>&3 2>&4
