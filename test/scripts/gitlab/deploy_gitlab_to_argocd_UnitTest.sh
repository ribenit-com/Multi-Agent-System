#!/bin/bash
# ===================================================
# GitLab -> ArgoCD UnitTest（动态等待 + Pod 就绪）
# ===================================================
set -euo pipefail

WORK_DIR=$(mktemp -d)
LOG_FILE="$WORK_DIR/test_run.log"

DEPLOY_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh"
DEPLOY_SCRIPT="./deploy_gitlab_to_argocd_.sh"

ARGO_APP="${ARGO_APP:-gitlab}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-gitlab}"
TIMEOUT="${TIMEOUT:-600}"   # 最大等待时间 10 分钟
SLEEP_INTERVAL=5            # 循环等待间隔

echo "🔹 工作目录: $WORK_DIR"
echo "🔹 日志文件: $LOG_FILE"

# -----------------------------
# 下载最新部署脚本
# -----------------------------
echo "🔹 下载最新部署脚本..."
curl -sSL "$DEPLOY_URL" -o "$DEPLOY_SCRIPT"
chmod +x "$DEPLOY_SCRIPT"
echo "✅ 最新部署脚本已下载: $DEPLOY_SCRIPT"

# 显示版本号
VERSION=$(grep -Eo '版本: v[0-9]+\.[0-9]+\.[0-9]+' "$DEPLOY_SCRIPT" || echo "未知版本")
echo "🔹 部署脚本版本: $VERSION"

# -----------------------------
# 执行部署脚本并保存日志
# -----------------------------
echo "🔹 执行部署脚本..."
if "$DEPLOY_SCRIPT" 2>&1 | tee "$LOG_FILE"; then
    echo "✅ 部署脚本执行完成"
else
    echo "❌ 部署脚本执行失败，请查看日志: $LOG_FILE"
    exit 1
fi

# -----------------------------
# 等待 ArgoCD Application 同步 + Pod 就绪
# -----------------------------
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
    STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    POD_READY=$(kubectl -n "$DEPLOY_NAMESPACE" get pods -l app=gitlab -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

    echo "⏱ [$ELAPSED s] ArgoCD Sync=$STATUS | Health=$HEALTH | PodReady=$POD_READY"

    if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" && "$POD_READY" == "true" ]]; then
        echo "✅ Application 同步完成且 Pod 就绪"
        break
    fi

    sleep $SLEEP_INTERVAL
    ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
done

# -----------------------------
# 输出 Deployment + Pod + Service 详细信息
# -----------------------------
echo "🔹 Deployment 状态:"
kubectl -n "$DEPLOY_NAMESPACE" get deployment gitlab -o wide | tee -a "$LOG_FILE"

echo "🔹 Pod 状态:"
kubectl -n "$DEPLOY_NAMESPACE" get pods -l app=gitlab -o wide | tee -a "$LOG_FILE"
kubectl -n "$DEPLOY_NAMESPACE" describe pod -l app=gitlab | tee -a "$LOG_FILE"

echo "🔹 Service 状态:"
kubectl -n "$DEPLOY_NAMESPACE" get svc gitlab -o wide | tee -a "$LOG_FILE"

# -----------------------------
# 最终结果判断
# -----------------------------
if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" && "$POD_READY" == "true" ]]; then
    echo "✅ UnitTest 验证通过"
    exit 0
else
    echo "❌ UnitTest 验证失败，请查看日志: $LOG_FILE"
    exit 1
fi
