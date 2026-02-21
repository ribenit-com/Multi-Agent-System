#!/bin/bash
# ===============================================
# GitLab HTTPS PAT 更新与验证脚本
# 功能：
#   1. 替换 Git 仓库的 HTTPS 密码为 PAT
#   2. 测试拉取仓库，确认认证有效
# ===============================================
set -euo pipefail

# ====== 配置区 ======
# GitLab 用户名（你的 GitLab 登录用户名或 email）
GITLAB_USER="your_username"

# GitLab 仓库 HTTPS URL（不要包含用户名）
REPO_URL="https://gitlab.com/namespace/project.git"

# Personal Access Token (PAT)
GITLAB_PAT="your_personal_access_token"

# 临时存放认证信息
CRED_HELPER="store"  # 或 "cache" 根据需求

# ====== 更新 Git 远程 URL ======
echo "🔹 设置远程 URL 带用户名"
git remote set-url origin "https://${GITLAB_USER}@${REPO_URL#https://}"

# ====== 配置 Git 凭证 helper ======
git config credential.helper $CRED_HELPER

# ====== 写入 PAT ======
echo "🔹 写入 PAT 到凭证缓存"
# store 模式会写到 ~/.git-credentials
echo "https://${GITLAB_USER}:${GITLAB_PAT}@${REPO_URL#https://}" | git credential approve

# ====== 测试拉取仓库 ======
echo "🔹 测试拉取仓库..."
if git ls-remote "$REPO_URL" &>/dev/null; then
    echo "✅ PAT 认证成功，仓库可访问"
else
    echo "❌ PAT 认证失败，请检查用户名、PAT 或权限"
    exit 1
fi
