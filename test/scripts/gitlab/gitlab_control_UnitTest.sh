#!/bin/bash
set -euo pipefail

#########################################
# GitLab YAML 生成脚本单元测试（增强版日志追踪）
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
# UT 断言工具
#########################################
fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_file_exists() { [ -f "$1" ] || fail "File $1 not found"; pass; }
assert_file_contains() { grep -q "$2" "$1" || fail "File $1 does not contain '$2'"; pass; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }

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
bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" "ns-test-gitlab" "sc-fast" "50Gi" "gitlab/gitlab-ce:15.0" "gitlab.test.local" "192.168.50.10" "35050" "30022" "30080"

#########################################
# UT 测试
#########################################

log "▶️ 检查 Namespace YAML..."
assert_file_exists "$TEST_DIR/${MODULE}_namespace.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "apiVersion: v1"
assert_file_contains "$TEST_DIR/${MODULE}_namespace.yaml" "name: ns-test-gitlab"

log "▶️ 检查 Secret YAML..."
assert_file_exists "$TEST_DIR/${MODULE}_secret.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_secret.yaml" "root-password"

log "▶️ 检查 StatefulSet YAML..."
assert_file_exists "$TEST_DIR/${MODULE}_statefulset.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "volumeClaimTemplates"
assert_file_contains "$TEST_DIR/${MODULE}_statefulset.yaml" "GITLAB_OMNIBUS_CONFIG"

log "▶️ 检查 Service YAML..."
assert_file_exists "$TEST_DIR/${MODULE}_service.yaml"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30080"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 30022"
assert_file_contains "$TEST_DIR/${MODULE}_service.yaml" "nodePort: 35050"

log "▶️ 检查 CronJob YAML..."
CRON_FILE="$TEST_DIR/${MODULE}_cronjob.yaml"
assert_file_exists "$CRON_FILE"

# 打印 CronJob 内容逐行
log "📌 CronJob YAML 内容:"
nl -w3 -s" | " "$CRON_FILE"

# 打印 command 内容
log "📌 CronJob containers.command 内容:"
grep -A10 "command:" "$CRON_FILE"

# 断言 registry-garbage-collect
assert_file_contains "$CRON_FILE" "registry-garbage-collect"
assert_file_contains "$CRON_FILE" "persistentVolumeClaim"

log "▶️ YAML 格式验证 (kubectl dry-run)..."
for f in namespace secret statefulset service cronjob; do
    kubectl apply --dry-run=client -f "$TEST_DIR/${MODULE}_$f.yaml" >/dev/null 2>&1 && pass || fail "$f YAML invalid"
done

log "▶️ 输出提示验证..."
EXPECTED_OUTPUT="✅ GitLab YAML 已生成到 $TEST_DIR"
bash "$TARGET_SCRIPT" "$MODULE" "$TEST_DIR" | grep -q "$EXPECTED_OUTPUT" && pass || fail "Output missing expected text"

log "🎉 所有 YAML 生成测试通过 (enterprise-level v1)"
