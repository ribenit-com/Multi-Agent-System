#!/bin/bash
# =========================================================
# GitLab -> ArgoCD 部署单体测试脚本（带状态码）
# 状态码说明：
#   0 → 所有操作成功
#   1 → 下载运行脚本失败
#   2 → 下载测试脚本失败
#   3 → 测试脚本执行失败
# =========================================================

set -euo pipefail

# 临时工作目录
WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/test_run.log"
cd "$WORK_DIR" || exit
echo "🔹 工作目录: $WORK_DIR"
echo "🔹 日志文件: $LOG_FILE"

# =========================
# 下载运行脚本
# =========================
RUN_SCRIPT="deploy_gitlab_to_argocd_.sh"
RUN_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"

echo "🔹 下载运行脚本: $RUN_SCRIPT"
if curl -fsSL "$RUN_URL" -o "$RUN_SCRIPT"; then
    chmod +x "$RUN_SCRIPT"
    echo "✅ 运行脚本下载完成"
else
    echo "❌ 运行脚本下载失败" | tee -a "$LOG_FILE"
    exit 1
fi

# =========================
# 下载测试脚本
# =========================
TEST_SCRIPT="deploy_gitlab_to_argocd_UnitTest.sh"
TEST_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/deploy_gitlab_to_argocd_UnitTest.sh"

echo "🔹 下载测试脚本: $TEST_SCRIPT"
if curl -fsSL "$TEST_URL" -o "$TEST_SCRIPT"; then
    chmod +x "$TEST_SCRIPT"
    echo "✅ 测试脚本下载完成"
else
    echo "❌ 测试脚本下载失败" | tee -a "$LOG_FILE"
    exit 2
fi

# =========================
# 执行测试脚本
# =========================
echo "🔹 开始执行测试脚本..."
if ./"$TEST_SCRIPT" 2>&1 | tee "$LOG_FILE"; then
    echo "✅ 测试执行成功"
else
    echo "❌ 测试执行失败，查看日志: $LOG_FILE"
    exit 3
fi

echo "🔹 所有操作完成，状态码: 0"
echo "🔹 临时目录保留: $WORK_DIR (可手动清理)"
exit 0
