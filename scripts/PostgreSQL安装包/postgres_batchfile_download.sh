#!/bin/bash
# ===================================================
# 脚本名称: postgres_batchfile_download.sh
# 功能:
#   - 批量下载 GitHub PostgreSQL 脚本
#   - 自动赋予可执行权限
# ===================================================

set -e

# ------------------------------
# GitHub 仓库基础路径
# ------------------------------
GITHUB_BASE="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/"

# ------------------------------
# 下载目录（本地）
# ------------------------------
DOWNLOAD_DIR="${HOME}/postgres_scripts"
mkdir -p "$DOWNLOAD_DIR"

# ------------------------------
# PostgreSQL 脚本列表
# ------------------------------
POSTGRES_SCRIPTS=(
    "Helm/setup_PostgreSQL_local.sh"
    "scripts/check_postgres_names_json.sh"
    "scripts/check_postgres_names_html.sh"
    "scripts/enterprise_master.sh"
    # 这里可以继续添加其他 PostgreSQL 相关脚本路径
)

# ------------------------------
# 批量下载
# ------------------------------
echo "🔹 开始下载 PostgreSQL 脚本到 $DOWNLOAD_DIR"

for SCRIPT_PATH in "${POSTGRES_SCRIPTS[@]}"; do
    FILE_NAME=$(basename "$SCRIPT_PATH")
    DOWNLOAD_URL="${GITHUB_BASE}${SCRIPT_PATH}"
    TARGET_FILE="$DOWNLOAD_DIR/$FILE_NAME"

    echo "⬇️ 下载 $FILE_NAME ..."
    curl -fsSL "$DOWNLOAD_URL" -o "$TARGET_FILE"

    # 赋予可执行权限
    chmod +x "$TARGET_FILE"
done

echo "✅ 所有 PostgreSQL 脚本下载完成，可执行文件在: $DOWNLOAD_DIR"
