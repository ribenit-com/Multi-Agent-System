#!/bin/bash
# ===================================================
# check_postgres_names_html.sh v1.3 单独执行版
# 功能：
#   - 生成 HTML 报告
#   - 支持传入 JSON 参数或指定 JSON 文件
# 参数：
#   $1 = 模块名（例如 PostgreSQL_HA）
#   $2 = JSON 内容 或 JSON 文件路径（可选，如果为空，则从 stdin 读取）
# ===================================================

MODULE="$1"
INPUT="$2"

# 检查模块名
if [[ -z "$MODULE" ]]; then
    echo "Usage: $0 <模块名> [JSON内容或JSON文件路径]"
    exit 1
fi

# 判断输入来源
if [[ -z "$INPUT" ]]; then
    # 从标准输入读取 JSON
    echo "ℹ️ 从标准输入读取 JSON..."
    JSON_RESULT=$(cat)
elif [[ -f "$INPUT" ]]; then
    # 如果是文件路径
    JSON_RESULT=$(cat "$INPUT")
else
    # 直接当作 JSON 内容
    JSON_RESULT="$INPUT"
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
