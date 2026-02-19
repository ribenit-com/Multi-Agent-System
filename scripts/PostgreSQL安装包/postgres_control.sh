#!/bin/bash
# ===================================================
# PostgreSQL 模块主控脚本
# 功能：
#  1. 调用 check_postgres_names_json.sh 获取 JSON
#  2. 调用 check_postgres_names_html.sh 生成 HTML 报告
# ===================================================

set -e

# ------------------------------
# JSON 临时文件
# ------------------------------
TMP_JSON="/tmp/postgres_check.json"

# ------------------------------
# 调用 JSON 检测脚本
# ------------------------------
echo "🔹 Step 1: 生成 PostgreSQL JSON 检测结果..."
./check_postgres_names_json.sh > "$TMP_JSON"

if [ ! -s "$TMP_JSON" ]; then
    echo "⚠️ JSON 检测结果为空，所有资源正常。"
fi

# ------------------------------
# 调用 HTML 报告生成脚本
# ------------------------------
echo "🔹 Step 2: 根据 JSON 生成 HTML 报告..."
./check_postgres_names_html.sh "$TMP_JSON"

echo "✅ HTML 报告生成完成。"
