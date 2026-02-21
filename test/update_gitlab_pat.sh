#!/bin/bash
set -euo pipefail

GITLAB_USER="zuandilong@gmail.com"
REPO_URL="https://github.com/ribenit-com/Multi-Agent-System.git"
GITLAB_PAT="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"
CRED_HELPER="store"

# 更新远程 URL
echo "🔹 设置远程 URL 带用户名"
git remote set-url origin "https://${GITLAB_USER}@${REPO_URL#https://}"

# 配置凭证 helper
git config credential.helper $CRED_HELPER

# 正确写入 PAT 到 store
echo "🔹 写入 PAT 到凭证缓存"
printf "protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n" "$GITLAB_USER" "$GITLAB_PAT" | git credential approve

# 测试仓库访问
echo "🔹 测试拉取仓库..."
if git ls-remote "$REPO_URL" &>/dev/null; then
    echo "✅ PAT 认证成功，仓库可访问"
else
    echo "❌ PAT 认证失败，请检查用户名、PAT 或权限"
    exit 1
fi
