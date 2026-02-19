#!/bin/bash
# ===================================================
# postgres_control.sh v2.0 修正版
# 功能：
#   1. 检测 PostgreSQL HA 资源命名
#   2. 生成 HTML 报告
#   3. 生成 GitOps YAML（修正调用 create_postgres_yaml.sh）
# ===================================================

set -e

MODULE="$1"
YAML_OUTPUT_DIR="$2"
CHECK_JSON_SCRIPT="$3"

if [[ -z "$MODULE" || -z "$YAML_OUTPUT_DIR" || -z "$CHECK_JSON_SCRIPT" ]]; then
    echo "Usage: $0 <模块名> <YAML输出目录> <检测脚本>"
    exit 1
fi

echo "🔹 postgres_control.sh v2.0"
echo "🔹 主控开始: 模块 = $MODULE"
echo ""

# 调用检测脚本生成 JSON
echo "🔹 调用检测脚本: $CHECK_JSON_SCRIPT"
JSON_RESULT=$(bash "$CHECK_JSON_SCRIPT")
echo "$JSON_RESULT"
echo ""

# 生成 HTML 报告
echo "🔹 check_postgres_names_html.sh v1.1"
bash ./check_postgres_names_html.sh "$MODULE" "$JSON_RESULT"
echo "✅ HTML 报告生成完成: /mnt/truenas/PostgreSQL安装报告书/${MODULE}_命名规约检测报告_$(date +%Y%m%d_%H%M%S).html"
echo "🔗 最新报告链接: /mnt/truenas/PostgreSQL安装报告书/latest.html"
echo ""

# ⚠️ 根据 JSON 触发报警/备份逻辑
# （保持原逻辑，这里省略具体实现）

# 生成 PostgreSQL HA GitOps YAML
echo "🔹 生成 PostgreSQL HA GitOps YAML：$YAML_OUTPUT_DIR"
mkdir -p "$YAML_OUTPUT_DIR"
bash ./create_postgres_yaml.sh "$MODULE" "$YAML_OUTPUT_DIR"

echo ""
echo "✅ GitOps YAML 生成完成: $YAML_OUTPUT_DIR"
