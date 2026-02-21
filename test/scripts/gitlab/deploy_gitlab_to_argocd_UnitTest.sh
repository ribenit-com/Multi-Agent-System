#!/bin/bash
# ===================================================
# GitLab -> ArgoCD UnitTest（自更新 + 版本号检查）
# ===================================================
set -euo pipefail

WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/test_run.log"

# -----------------------------
# 部署脚本 URL
# -----------------------------
DEPLOY_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"
DEPLOY_SCRIPT="./deploy_gitlab_to_argocd_.sh"

echo "🔹 工作目录: $WORK_DIR"
echo "🔹 日志文件: $LOG_FILE"
echo "🔹 下载并执行最新部署脚本: $DEPLOY_URL"

# -----------------------------
# 下载最新部署脚本
# -----------------------------
curl -sSL "$DEPLOY_URL" -o "$DEPLOY_SCRIPT"
chmod +x "$DEPLOY_SCRIPT"
echo "✅ 最新部署脚本已下载: $DEPLOY_SCRIPT"

# -----------------------------
# 显示版本号
# -----------------------------
VERSION=$(grep -Eo '版本: v[0-9]+\.[0-9]+\.[0-9]+' "$DEPLOY_SCRIPT" || echo "未知版本")
echo "🔹 部署脚本版本: $VERSION"

# -----------------------------
# 执行部署脚本并记录日志
# -----------------------------
echo "🔹 执行部署脚本..."
if "$DEPLOY_SCRIPT" 2>&1 | tee "$LOG_FILE"; then
    echo "✅ 部署脚本执行完成"
else
    echo "❌ 部署脚本执行失败，请查看日志: $LOG_FILE"
    exit 1
fi

# -----------------------------
# 验证 ArgoCD Application 状态
# -----------------------------
ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

echo "🔹 最终状态: Sync=$STATUS | Health=$HEALTH"

if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo "✅ UnitTest 验证通过"
    exit 0
else
    echo "❌ UnitTest 验证失败"
    exit 1
fi
