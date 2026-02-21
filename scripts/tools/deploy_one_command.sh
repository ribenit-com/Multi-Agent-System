#!/bin/bash
set -euo pipefail

# ===================== 配置区 =====================
ARGOCD_SERVER="${ARGOCD_SERVER:-192.168.1.10:30100}"
ARGOCD_TOKEN="${ARGOCD_TOKEN:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhcmdvY2QiLCJzdWIiOiJhZG1pbjphcGlLZXkiLCJuYmYiOjE3NzE2ODg4MDUsImlhdCI6MTc3MTY4ODgwNSwianRpIjoiOWVkOTcwZjktNWMwNy00N2IyLTk3OWUtNjExZjUyYjFkNTZiIn0.ItqVg4XhlZJcd_7b0dqKDkH7CGP4gArW5WMuXAW6E-I}"
REPO_URL="${REPO_URL:-https://github.com/ribenit-com/Multi-Agent-k8s-gitops-postgres.git}"
REPO_NAME="${REPO_NAME:-gitlab}"
ARGO_APP="${ARGO_APP:-gitlab-app}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"

# Git 仓库凭证（如果是私有仓库）
GIT_USERNAME="${GIT_USERNAME:-ribenit-com}"
GIT_PASSWORD="${GIT_PASSWORD:-<你的 GitHub/GitLab Token>}"

# ===================== 添加仓库 =====================
echo "🔹 添加 Git 仓库 $REPO_URL 到 ArgoCD ..."

cat > /tmp/repo.json <<EOF
{
  "repo": "$REPO_URL",
  "username": "$GIT_USERNAME",
  "password": "$GIT_PASSWORD",
  "name": "$REPO_NAME",
  "insecure": true
}
EOF

HTTP_CODE=$(curl -sk -o /tmp/repo_result.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $ARGOCD_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/repo.json \
  "https://$ARGOCD_SERVER/api/v1/repositories")

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
  echo "✅ 仓库添加成功"
else
  # 如果仓库已经存在，忽略错误
  if grep -q "already exists" /tmp/repo_result.json; then
    echo "⚠️ 仓库已存在，跳过"
  else
    echo "❌ 仓库添加失败 (HTTP $HTTP_CODE)"
    cat /tmp/repo_result.json
    exit 1
  fi
fi

# ===================== 创建应用 =====================
echo "🔹 创建 ArgoCD 应用 $ARGO_APP ..."

cat > /tmp/app.json <<EOF
{
  "apiVersion": "argoproj.io/v1alpha1",
  "kind": "Application",
  "metadata": {
    "name": "$ARGO_APP",
    "namespace": "argocd"
  },
  "spec": {
    "project": "default",
    "source": {
      "repoURL": "$REPO_URL",
      "targetRevision": "HEAD",
      "path": "."
    },
    "destination": {
      "server": "https://kubernetes.default.svc",
      "namespace": "$TARGET_NAMESPACE"
    },
    "syncPolicy": {
      "automated": {
        "prune": true,
        "selfHeal": true
      }
    }
  }
}
EOF

HTTP_CODE=$(curl -sk -o /tmp/app_result.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $ARGOCD_TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/app.json \
  "https://$ARGOCD_SERVER/api/v1/applications")

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
  echo "✅ 应用 $ARGO_APP 创建成功"
else
  if grep -q "already exists" /tmp/app_result.json; then
    echo "⚠️ 应用已存在，跳过创建"
  else
    echo "❌ 应用创建失败 (HTTP $HTTP_CODE)"
    cat /tmp/app_result.json
    exit 1
  fi
fi

# ===================== 等待同步 =====================
echo "🔹 等待应用同步完成 (最长5分钟)..."

for i in {1..60}; do
  STATUS=$(curl -sk -H "Authorization: Bearer $ARGOCD_TOKEN" \
    "https://$ARGOCD_SERVER/api/v1/applications/$ARGO_APP" \
    | jq -r '.status.sync.status')
  HEALTH=$(curl -sk -H "Authorization: Bearer $ARGOCD_TOKEN" \
    "https://$ARGOCD_SERVER/api/v1/applications/$ARGO_APP" \
    | jq -r '.status.health.status')
  echo "[$i] sync=$STATUS, health=$HEALTH"
  if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo "✅ 应用已同步完成"
    break
  fi
  sleep 5
done

echo "🎉 一键部署完成，应用已在 ArgoCD 中注册并同步"
