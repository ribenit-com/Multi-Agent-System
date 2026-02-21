#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署单体测试脚本 v1.1.0
# ===================================================
set -euo pipefail

WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/test_run.log"
cd "$WORK_DIR" || exit

echo "🔹 工作目录: $WORK_DIR"
echo "🔹 日志文件: $LOG_FILE"

# -----------------------------
# 下载最新部署脚本
# -----------------------------
RUN_SCRIPT="deploy_gitlab_to_argocd_.sh"
RUN_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"

echo "🔹 下载最新部署脚本..."
curl -sSL "$RUN_URL" -o "$RUN_SCRIPT"
chmod +x "$RUN_SCRIPT"
echo "✅ 最新部署脚本已下载: ./$RUN_SCRIPT"

# -----------------------------
# 执行部署脚本
# -----------------------------
echo "🔹 执行部署脚本..."
if ./"$RUN_SCRIPT" 2>&1 | tee "$LOG_FILE"; then
    echo "✅ 部署脚本执行完成"
else
    echo "❌ 部署脚本执行失败，请查看日志: $LOG_FILE"
    exit 1
fi

echo "🔹 测试完成"
exit 0
