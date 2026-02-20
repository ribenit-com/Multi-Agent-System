#!/bin/bash
# ===================================================
# check_gitlab_names_html.sh v3.1
# 功能：生成 GitLab 命名规约 HTML 报告
# 参数：
#   $1 = 模块名
#   $2 = JSON 文件路径
# ===================================================

set -e

MODULE="$1"
JSON_FILE="$2"

# -------------------------------
# 参数检查
# -------------------------------
if [[ -z "$MODULE" ]]; then
    echo "❌ 模块名未提供"
    exit 1
fi

if [[ -z "$JSON_FILE" || ! -f "$JSON_FILE" ]]; then
    echo "❌ JSON 文件不存在或未提供: $JSON_FILE"
    exit 1
fi

# -------------------------------
# 输出目录与文件
# -------------------------------
OUTPUT_DIR="/mnt/truenas/PostgreSQL安装报告书"
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/${MODULE}_命名规约检测报告_${TIMESTAMP}.html"

# -------------------------------
# HTML 特殊字符转义
# -------------------------------
ESCAPED_JSON=$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' < "$JSON_FILE")

# -------------------------------
# HTML 报告生成
# -------------------------------
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
    <pre>$ESCAPED_JSON</pre>
</body>
</html>
EOF

# -------------------------------
# 更新 latest.html 链接
# -------------------------------
ln -sf "$OUTPUT_FILE" "$OUTPUT_DIR/latest.html"

# -------------------------------
# 输出完成信息
# -------------------------------
echo "✅ HTML 报告生成完成: $OUTPUT_FILE"
echo "🔗 最新报告链接: $OUTPUT_DIR/latest.html"
