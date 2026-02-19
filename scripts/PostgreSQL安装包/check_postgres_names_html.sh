#!/bin/bash
# ===================================================
# check_postgres_names_html.sh v1.2 修正版
# 功能：
#   - 生成 HTML 报告
# 参数：
#   $1 = 模块名（例如 PostgreSQL_HA）
#   $2 = JSON 内容（由 check_postgres_names_json.sh 输出）
# ===================================================

MODULE="$1"
JSON_RESULT="$2"

if [[ -z "$MODULE" || -z "$JSON_RESULT" ]]; then
    echo "Usage: $0 <模块名> <JSON内容>"
    exit 1
fi

# 设置 HTML 输出目录
OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"
mkdir -p "$OUTPUT_DIR"

# 生成 HTML 文件名
OUTPUT_FILE="$OUTPUT_DIR/${MODULE}_命名规约检测报告_$(date +%Y%m%d_%H%M%S).html"

# 生成 HTML 内容
cat <<EOF > "$OUTPUT_FILE"
<html>
<head>
    <meta charset="UTF-8">
    <title>$MODULE 命名规约检测报告</title>
</head>
<body>
    <h1>$MODULE 命名规约检测报告</h1>
    <pre>$JSON_RESULT</pre>
</body>
</html>
EOF

# 更新 latest.html 快捷链接
ln -sf "$OUTPUT_FILE" "$OUTPUT_DIR/latest.html"

echo "✅ HTML 报告生成完成: $OUTPUT_FILE"
echo "🔗 最新报告链接: $OUTPUT_DIR/latest.html"
