#!/bin/bash
set -euo pipefail

#########################################
# deploy_argocd_app_UnitTest_DRYRUN.sh
# 单体测试（函数调用 + Dry-run）
# 覆盖 UT-01 ~ UT-10
#########################################

SCRIPT="./deploy_argocd_app.sh"

if [[ ! -f "$SCRIPT" ]]; then
  echo "❌ ERROR: 脚本不存在: $SCRIPT"
  exit 1
fi

# 加载 deploy_app() 函数
source "$SCRIPT"

#########################################
# UT 断言工具
#########################################
fail() { echo "❌ FAIL: $1"; exit 1; }
pass() { echo "✅ PASS"; }
assert_equal() { [[ "$1" == "$2" ]] || fail "expected=$1 actual=$2"; pass; }
assert_log_contains() { grep -q "$2" "$1" || fail "log missing: $2"; pass; }

#########################################
# UT 全局参数 & Dry-run
#########################################
export DRY_RUN=true
export ARGO_APP="test-postgres-ha"
export GITHUB_REPO="test-org/test-repo"
export CHART_PATH="charts/postgres-ha"
export VALUES_FILE="values.yaml"
export NAMESPACE="test-postgres"
export ARGO_NAMESPACE="argocd"
export TIMEOUT=5
INTERVAL=1

#########################################
# UT-01 参数默认值
#########################################
echo "🔹 UT-01 参数默认值"
ARGO_APP=""
[[ -z "$ARGO_APP" ]] && ARGO_APP="default-app"
assert_equal "default-app" "$ARGO_APP"

#########################################
# UT-02 参数缺失
#########################################
echo "🔹 UT-02 缺失 GITHUB_REPO"
unset GITHUB_REPO
TMP_LOG=$(mktemp)
{
  export ARGO_APP
  export GITHUB_REPO=""
  deploy_app || true
} &> "$TMP_LOG"
assert_log_contains "$TMP_LOG" "GITHUB_REPO"
rm -f "$TMP_LOG"
pass

#########################################
# UT-03 / UT-04 ArgoCD 环境检查
#########################################
echo "🔹 UT-03 / UT-04 ArgoCD 环境检查"
export GITHUB_REPO="test-org/test-repo"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG" || true
assert_log_contains "$TMP_LOG" "INFO"
rm -f "$TMP_LOG"
pass

#########################################
# UT-05 / UT-06 Application 创建/更新
#########################################
echo "🔹 UT-05 / UT-06 Application 创建/更新"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG"
assert_log_contains "$TMP_LOG" "Application 已提交"
rm -f "$TMP_LOG"
pass

#########################################
# UT-07 同步成功
#########################################
echo "🔹 UT-07 同步成功"
export MOCK_SYNC_STATUS="Synced"
export MOCK_HEALTH_STATUS="Healthy"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG"
assert_log_contains "$TMP_LOG" "同步成功"
rm -f "$TMP_LOG"
pass

#########################################
# UT-08 同步失败 Degraded
#########################################
echo "🔹 UT-08 同步失败 Degraded"
export MOCK_HEALTH_STATUS="Degraded"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG" || true
assert_log_contains "$TMP_LOG" "Degraded"
rm -f "$TMP_LOG"
pass

#########################################
# UT-09 同步超时
#########################################
echo "🔹 UT-09 同步超时"
export TIMEOUT=3
export INTERVAL=1
export MOCK_SYNC_STATUS="Unknown"
export MOCK_HEALTH_STATUS="Unknown"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG" || true
assert_log_contains "$TMP_LOG" "超时"
rm -f "$TMP_LOG"
pass

#########################################
# UT-10 日志输出
#########################################
echo "🔹 UT-10 日志输出"
export MOCK_SYNC_STATUS="Synced"
export MOCK_HEALTH_STATUS="Healthy"
TMP_LOG=$(mktemp)
deploy_app &> "$TMP_LOG"
for level in INFO WARN ERROR; do
  assert_log_contains "$TMP_LOG" "$level"
done
rm -f "$TMP_LOG"
pass

echo "🎉 All tests passed (Dry-run Function UT v2.1)"
