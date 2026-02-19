#!/bin/bash
# ===================================================
# check_postgres_names_html.sh v2.0
# 功能：生成 HTML 报告
# 参数：
#   $1 = 模块名
#   $2 = JSON 文件路径（优化为文件）
# ===================================================

MODULE="$1"
JSON_FILE="$2"

if [[ -z "$MODULE" || -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
    echo "Usage: $0 <模块名> <JSON文件路径>"
    exit 1
fi

OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/${MODULE}_命名规约检测报告_$(date +%Y%m%d_%H%M%S).html"

# 转义 HTML 特殊字符
ESCAPED_JSON=$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' < "$JSON_FILE")

cat <<EOF > "$OUTPUT_FILE"
<html>
<head>
    <meta charset="UTF-8">
    <title>$MODULE 命名规约检测报告</title>
    <style>
        body { font-family: monospace; background: #f4f4f4; padding: 20px; }
        pre { background: #fff; padding: 10px; border: 1px solid #ccc; overflow-x: auto; }
        h1 { color: #2c3e50; }
    </style>
</head>
<body>
    <h1>$MODULE 命名规约检测报告</h1>
    <pre>$ESCAPED_JSON</pre>
</body>
</html>
EOF

ln -sf "$OUTPUT_FILE" "$OUTPUT_DIR/latest.html"

echo "✅ HTML 报告生成完成: $OUTPUT_FILE"
echo "🔗 最新报告链接: $OUTPUT_DIR/latest.html"
