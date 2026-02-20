#!/bin/bash
# ===================================================
# check_postgres_names_html.sh v3.0
# 功能：生成 HTML 报告（兼容 UT-01 ~ UT-08）
# 参数：
#   $1 = 模块名
#   $2 = JSON 文件路径
# ===================================================

set -e

MODULE="$1"
JSON_FILE="$2"

#########################################
# 1️⃣ 参数校验
#########################################

if [[ -z "$MODULE" || -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
    echo "Usage: $0 <模块名> <JSON文件路径>"
    exit 1
fi

#########################################
# 2️⃣ 输出目录
#########################################

OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"

mkdir -p "$OUTPUT_DIR"

#########################################
# 3️⃣ 生成输出文件名（带时间戳）
#########################################

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/${MODULE}_命名规约检测报告_${TIMESTAMP}.html"

#########################################
# 4️⃣ HTML 特殊字符转义
#########################################

ESCAPED_JSON=$(sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    < "$JSON_FILE")

#########################################
# 5️⃣ 写入 HTML
#########################################

cat <<EOF > "$OUTPUT_FILE"
<html>
<head>
    <meta charset="UTF-8">
    <title>${MODULE} 命名规约检测报告</title>
    <style>
        body { font-family: monospace; background: #f4f4f4; padding: 20px; }
        pre { background: #fff; padding: 10px; border: 1px solid #ccc; overflow-x: auto; }
        h1 { color: #2c3e50; }
    </style>
</head>
<body>
    <h1>${MODULE} 命名规约检测报告</h1>
    <pre>${ESCAPED_JSON}</pre>
</body>
</html>
EOF

#########################################
# 6️⃣ 更新 latest 软链接
#########################################

ln -sf "$OUTPUT_FILE" "$OUTPUT_DIR/latest.html"

#########################################
# 7️⃣ 输出成功信息（供 UT-08 检测）
#########################################

echo "✅ HTML 报告生成完成: $OUTPUT_FILE"
echo "🔗 最新报告链接: $OUTPUT_DIR/latest.html"
