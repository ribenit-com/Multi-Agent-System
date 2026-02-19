#!/bin/bash
# ===================================================
# PostgreSQL HA 脚本批量下载
# 功能：
#   1. 下载主控脚本
#   2. 下载 JSON 检测脚本
#   3. 下载 HTML 报告脚本
#   4. 赋可执行权限
# ===================================================

set -e

# 工作目录
WORK_DIR=~/postgres_ha_scripts
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "⬇️ 下载 PostgreSQL HA 主控脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/postgres_control.sh" -o postgres_control.sh

echo "⬇️ 下载 JSON 检测脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh" -o check_postgres_names_json.sh

echo "⬇️ 下载 HTML 报告脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh" -o check_postgres_names_html.sh

echo "⬇️ 下载 YAML 生成脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/create_postgres_yaml.sh" -o create_postgres_yaml.sh

# 赋可执行权限
chmod +x *.sh

echo "✅ PostgreSQL HA 脚本下载完成"
echo "📁 脚本目录: $WORK_DIR"
echo "可执行主控脚本: ./postgres_control.sh \"PostgreSQL_HA\" ./check_postgres_names_json.sh"
