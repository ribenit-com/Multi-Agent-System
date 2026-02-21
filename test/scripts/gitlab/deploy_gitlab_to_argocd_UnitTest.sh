#!/bin/bash
# ===================================================
# GitLab -> ArgoCD 部署单体测试脚本（新版）
# ===================================================
set -euo pipefail

WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/test_run.log"
DEPLOY_SCRIPT="./deploy_gitlab_to_argocd_.sh"

echo "🔹 工作目录: $WORK_DIR"
echo "🔹 日志文件: $LOG_FILE"

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    echo "❌ 部署脚本 $DEPLOY_SCRIPT 不存在"
    exit 1
fi

chmod +x "$DEPLOY_SCRIPT"

echo "🔹 执行部署脚本..."
if "$DEPLOY_SCRIPT" 2>&1 | tee "$LOG_FILE"; then
    echo "✅ 部署脚本执行完成"
else
    echo "❌ 部署脚本执行失败，请查看日志: $LOG_FILE"
    exit 1
fi

ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

echo "🔹 最终状态: Sync=$STATUS | Health=$HEALTH"

if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo "✅ UnitTest 验证通过，应用已同步且健康"
    exit 0
else
    echo "❌ UnitTest 验证失败，应用未同步或不健康"
    exit 1
fi
