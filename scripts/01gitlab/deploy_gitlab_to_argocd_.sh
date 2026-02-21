#!/bin/bash
set -euo pipefail

#############################################
# ArgoCD Deployment Script (Production Ready)
# Version: 1.0
#############################################

#############################
# 基础参数（可外部传入）
#############################

ARGO_APP="${ARGO_APP:-postgres-ha}"
GITHUB_REPO="${GITHUB_REPO:-your-org/your-repo}"
CHART_PATH="${CHART_PATH:-postgres-ha-chart}"
VALUES_FILE="${VALUES_FILE:-values.yaml}"
NAMESPACE="${NAMESPACE:-postgres}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argocd}"

TIMEOUT="${TIMEOUT:-900}"      # 最大等待时间（秒）
INTERVAL=5                     # 轮询间隔

#############################
# 日志函数
#############################

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

info() {
  log "INFO  - $1"
}

warn() {
  log "WARN  - $1"
}

error() {
  log "ERROR - $1"
}

#############################
# 环境检查
#############################

info "检查 ArgoCD 是否存在..."

if ! kubectl get ns "$ARGO_NAMESPACE" >/dev/null 2>&1; then
  error "ArgoCD namespace '$ARGO_NAMESPACE' 不存在"
  exit 1
fi

if ! kubectl -n "$ARGO_NAMESPACE" get deploy argocd-server >/dev/null 2>&1; then
  error "ArgoCD server 未运行"
  exit 1
fi

info "ArgoCD 环境正常"

#############################
# 创建 / 更新 Application
#############################

info "创建 / 更新 ArgoCD Application: $ARGO_APP"

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${ARGO_APP}
  namespace: ${ARGO_NAMESPACE}
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_REPO}.git
    targetRevision: main
    path: ${CHART_PATH}
    helm:
      valueFiles:
        - ${VALUES_FILE}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
EOF

info "Application 已提交给 ArgoCD"

#############################
# 等待同步完成
#############################

info "开始等待 ArgoCD 同步完成 (timeout=${TIMEOUT}s)"

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do

  STATUS=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

  HEALTH=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")

  REVISION=$(kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" \
    -o jsonpath='{.status.sync.revision}' 2>/dev/null || echo "N/A")

  info "进度: ${ELAPSED}/${TIMEOUT}s | sync=${STATUS} | health=${HEALTH} | revision=${REVISION}"

  # 成功
  if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    info "ArgoCD Application 同步成功"
    exit 0
  fi

  # 明确失败
  if [[ "$HEALTH" == "Degraded" ]]; then
    error "Application 状态异常 (Degraded)"
    kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o yaml
    exit 1
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

#############################
# 超时处理
#############################

error "ArgoCD 同步超时 (${TIMEOUT}s)"
warn "打印 Application 当前状态用于排查"

kubectl -n "$ARGO_NAMESPACE" get app "$ARGO_APP" -o yaml

exit 1
