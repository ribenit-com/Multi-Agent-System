#!/bin/bash
# ===================================================
# PostgreSQL HA 自动执行脚本
# 功能：
#   - 下载三个独立脚本（JSON/HTML/主控）
#   - 赋予可执行权限
#   - 执行主控脚本生成 JSON + HTML 报告
# ===================================================

set -e
set -o pipefail
set -x

# ------------------------------
# 配置目录
# ------------------------------
WORK_DIR=~/postgres_ha_scripts
MODULE="PostgreSQL_HA"
HTML_OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

mkdir -p "$WORK_DIR" "$HTML_OUTPUT_DIR"
chmod 755 "$WORK_DIR" "$HTML_OUTPUT_DIR"
cd "$WORK_DIR"

# ------------------------------
# 下载独立脚本
# ------------------------------
echo "⬇️ 下载 JSON 检测脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh" -o check_postgres_names_json.sh

echo "⬇️ 下载 HTML 报告脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh" -o check_postgres_names_html.sh

echo "⬇️ 下载主控脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/postgres_control.sh" -o postgres_control.sh

chmod +x check_postgres_names_json.sh check_postgres_names_html.sh postgres_control.sh

# ------------------------------
# 执行主控脚本
# ------------------------------
echo "🔹 执行主控脚本: postgres_control.sh"
./postgres_control.sh "$MODULE" ./check_postgres_names_json.sh

echo ""
echo "✅ PostgreSQL HA 主控执行完成"
echo "📁 HTML 报告目录: $HTML_OUTPUT_DIR"
echo "📁 脚本工作目录: $WORK_DIR"
