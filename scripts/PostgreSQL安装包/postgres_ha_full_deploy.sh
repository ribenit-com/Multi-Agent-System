#!/bin/bash
# ===================================================
# PostgreSQL HA 执行命令生成器（下载 + 命令打印）
# 功能：
#   - 下载三个独立脚本（JSON/HTML/YAML）
#   - 打印执行命令，方便手动运行
# ===================================================

set -e
set -o pipefail
set -x

# ------------------------------
# 配置目录
# ------------------------------
WORK_DIR=~/postgres_ha_scripts
MODULE="PostgreSQL_HA"
YAML_OUTPUT_DIR="$WORK_DIR/gitops/postgres-ha"
HTML_OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

mkdir -p "$WORK_DIR" "$YAML_OUTPUT_DIR" "$HTML_OUTPUT_DIR"
chmod 755 "$WORK_DIR" "$YAML_OUTPUT_DIR" "$HTML_OUTPUT_DIR"
cd "$WORK_DIR"

# ------------------------------
# 下载独立脚本
# ------------------------------
echo "⬇️ 下载 JSON 检测脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh" -o check_postgres_names_json.sh
echo "⬇️ 下载 HTML 报告脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh" -o check_postgres_names_html.sh
echo "⬇️ 下载 GitOps YAML 生成脚本"
curl -fsSL "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/generate_postgres_ha_yaml.sh" -o generate_postgres_ha_yaml.sh

chmod +x check_postgres_names_json.sh check_postgres_names_html.sh generate_postgres_ha_yaml.sh

# ------------------------------
# 打印手动执行命令
# ------------------------------
echo ""
echo "🔹 PostgreSQL HA 手动执行命令清单"
echo "----------------------------------------"

# JSON 检测
echo ""
echo "1️⃣ JSON 检测（生成 JSON 数据）:"
echo "cd $WORK_DIR"
echo "./check_postgres_names_json.sh > json_result.json"
echo "cat json_result.json"

# HTML 报告生成
echo ""
echo "2️⃣ HTML 报告生成（从 JSON 生成 HTML）:"
echo "cd $WORK_DIR"
echo "./check_postgres_names_html.sh $MODULE \$(cat json_result.json)"

# GitOps YAML 生成
echo ""
echo "3️⃣ GitOps YAML 生成（从 JSON 生成 YAML）:"
echo "cd $WORK_DIR"
echo "cat json_result.json | ./generate_postgres_ha_yaml.sh"

echo ""
echo "✅ 以上命令按顺序手动执行即可完成 PostgreSQL HA 部署准备"
echo "📁 JSON 输出目录: $WORK_DIR"
echo "📁 YAML 输出目录: $YAML_OUTPUT_DIR"
echo "📁 HTML 报告目录: $HTML_OUTPUT_DIR"
