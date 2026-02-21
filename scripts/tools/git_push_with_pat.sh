#!/bin/bash
# ===============================================
# 一键安全上传 GitHub 代码脚本（PAT 自动配置 + Push）
# 使用场景：安全、跨平台，一次执行完成 PAT 配置和代码上传
# ===============================================
set -euo pipefail

# ====== 配置区 ======
GITLAB_USER="zuandilong@gmail.com"
GITLAB_PAT="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"
REPO_URL="https://github.com/ribenit-com/Multi-Agent-System.git"
BRANCH="${1:-main}"  # 默认 main 分支，可传参覆盖

COMMIT_MSG="${2:-自动上传代码 $(date '+%Y-%m-%d %H:%M:%S')}"

# ====== 自动选择安全凭证 helper ======
OS_TYPE=$(uname | tr '[:upper:]' '[:lower:]')
if [[ "$OS_TYPE" == "darwin" ]]; then
    CRED_HELPER="osxkeychain"
elif [[ "$OS_TYPE" == "linux" ]]; then
    CRED_HELPER="cache --timeout=3600"  # 1小时
elif [[ "$OS_TYPE" == "mingw"* || "$OS_TYPE" == "cygwin"* || "$OS_TYPE" == "msys"* ]]; then
    CRED_HELPER="manager-core"
else
    echo "⚠️ 未知系统，默认使用 store（明文）"
    CRED_HELPER="store"
fi

echo "🔹 使用凭证 helper: $CRED_HELPER"
git config credential.helper "$CRED_HELPER"

# ====== 更新远程 URL ======
echo "🔹 设置远程 URL 带用户名"
git remote set-url origin "https://${GITLAB_USER}@${REPO_URL#https://}"

# ====== 写入 PAT ======
echo "🔹 写入 PAT 到凭证缓存"
printf "protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n" "$GITLAB_USER" "$GITLAB_PAT" | git credential approve

# ====== 测试仓库访问 ======
echo "🔹 测试拉取仓库..."
if git ls-remote "$REPO_URL" &>/dev/null; then
    echo "✅ PAT 认证成功，仓库可访问"
else
    echo "❌ PAT 认证失败，请检查用户名、PAT 或权限"
    exit 1
fi

# ====== 自动上传代码 ======
echo "🔹 添加修改并提交"
git add .

echo "🔹 提交信息: $COMMIT_MSG"
git commit -m "$COMMIT_MSG" || echo "⚠️ 没有新修改，跳过 commit"

echo "🔹 推送到远程分支: $BRANCH"
git push origin "$BRANCH"

echo "🎉 代码已成功上传到 $BRANCH 分支"
