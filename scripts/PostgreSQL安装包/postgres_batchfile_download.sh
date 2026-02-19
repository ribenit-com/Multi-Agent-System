#!/bin/bash
# ===================================================
# PostgreSQL HA 一键部署脚本
# 功能：
#   1. 下载所有脚本
#   2. 赋可执行权限
#   3. 执行主控生成 JSON、HTML 报告和 YAML
# ===================================================

set -e

# ------------------------------
# 配置
# ------------------------------
WORK_DIR=~/postgres_ha_scripts
MODULE="PostgreSQL_HA"
YAML_OUTPUT_DIR="./gitops/postgres-ha"

# JSON 检测脚本 URL
CHECK_JSON_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh"
# HTML 报告脚本 URL
CHECK_HTML_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh"
# 主控脚本 URL
CONTROL_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/postgres_control.sh"
# YAML 生成脚本 URL
YAML_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/create_postgres_yaml.sh"

# ------------------------------
# 创建工作目录
# ------------------------------
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ------------------------------
# 下载脚本
# ------------------------------
echo "⬇️ 下载 PostgreSQL HA 主控脚本"
curl -fsSL "$CONTROL_URL" -o postgres_control.sh

echo "⬇️ 下载 JSON 检测脚本"
curl -fsSL "$CHECK_JSON_URL" -o check_postgres_names_json.sh

echo "⬇️ 下载 HTML 报告脚本"
curl -fsSL "$CHECK_HTML_URL" -o check_postgres_names_html.sh

echo "⬇️ 下载 YAML 生成脚本"
curl -fsSL "$YAML_URL" -o create_postgres_yaml.sh

# ------------------------------
# 赋可执行权限
# ------------------------------
chmod +x *.sh

# ------------------------------
# 执行主控生成 JSON + HTML + YAML
# ------------------------------
echo "🔹 执行主控脚本生成报告和 YAML"
./postgres_control.sh "$MODULE" "$YAML_OUTPUT_DIR" ./check_postgres_names_json.sh

echo ""
echo "✅ PostgreSQL HA 全流程完成"
echo "📁 脚本目录: $WORK_DIR"
echo "📁 YAML 输出目录: $YAML_OUTPUT_DIR"
echo "📁 HTML 报告目录: /mnt/truenas/PostgreSQL安装报告书"
