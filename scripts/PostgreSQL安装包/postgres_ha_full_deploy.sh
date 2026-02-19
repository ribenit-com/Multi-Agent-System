#!/bin/bash
# ===================================================
# PostgreSQL HA 一键部署（完全自动化版）
# 功能：
#   - 下载脚本
#   - 创建目录并修复权限
#   - 执行主控生成 JSON、HTML 报告和 YAML
# ===================================================

set -e
set -o pipefail
set -x   # 打开调试输出

# ------------------------------
# 配置
# ------------------------------
WORK_DIR=~/postgres_ha_scripts
MODULE="PostgreSQL_HA"
YAML_OUTPUT_DIR="$WORK_DIR/gitops/postgres-ha"
HTML_OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

# ------------------------------
# 脚本 URL（HTML 使用修正版 v1.2）
# ------------------------------
CONTROL_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/postgres_control.sh"
CHECK_JSON_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh"
CHECK_HTML_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh"
YAML_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/create_postgres_yaml.sh"

# ------------------------------
# 创建工作目录和输出目录
# ------------------------------
mkdir -p "$WORK_DIR" "$YAML_OUTPUT_DIR" "$HTML_OUTPUT_DIR"
chmod 755 "$WORK_DIR" "$YAML_OUTPUT_DIR" "$HTML_OUTPUT_DIR"
cd "$WORK_DIR"

# ------------------------------
# 下载脚本
# ------------------------------
echo "⬇️ 下载 PostgreSQL HA 主控脚本"
curl -fsSL "$CONTROL_URL" -o postgres_control.sh

echo "⬇️ 下载 JSON 检测脚本"
curl -fsSL "$CHECK_JSON_URL" -o check_postgres_names_json.sh

echo "⬇️ 下载 HTML 修正版脚本"
curl -fsSL "$CHECK_HTML_URL" -o check_postgres_names_html.sh

echo "⬇️ 下载 YAML 生成脚本"
curl -fsSL "$YAML_URL" -o create_postgres_yaml.sh

chmod +x *.sh

# ------------------------------
# 执行主控生成 JSON + HTML + YAML
# ------------------------------
echo "🔹 执行 JSON 检测"
JSON_RESULT=$(bash ./check_postgres_names_json.sh)

echo "🔹 生成 HTML 报告"
bash ./check_postgres_names_html.sh "$MODULE" "$JSON_RESULT"

echo "🔹 生成 GitOps YAML"
bash ./create_postgres_yaml.sh "$YAML_OUTPUT_DIR"

echo ""
echo "✅ PostgreSQL HA 全流程完成"
echo "📁 脚本目录: $WORK_DIR"
echo "📁 YAML 输出目录: $YAML_OUTPUT_DIR"
echo "📁 HTML 报告目录: $HTML_OUTPUT_DIR"
echo "🔗 最新 HTML 报告链接: $HTML_OUTPUT_DIR/latest.html"
