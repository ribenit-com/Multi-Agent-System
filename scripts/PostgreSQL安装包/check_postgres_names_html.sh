#!/bin/bash
# ===================================================
# 脚本名称: check_postgres_names_html.sh
# 功能: 根据 JSON 数据生成 PostgreSQL HA 命名规约 HTML 报告
#       - 接收 JSON 文件路径作为参数
# ===================================================

set -e

JSON_FILE="$1"

if [ -z "$JSON_FILE" ] || [ ! -f "$JSON_FILE" ]; then
    echo "❌ 请提供有效的 JSON 文件路径"
    exit 1
fi

# ------------------------------
# 读取 JSON 数据
# ------------------------------
JSON_DATA=$(cat "$JSON_FILE")

# ------------------------------
# 报告目录
# ------------------------------
BASE_DIR="/mnt/truenas"
REPORT_DIR="$BASE_DIR/PostgreSQL安装报告书"
mkdir -p "$REPORT_DIR"
HTML_FILE="$REPORT_DIR/PostgreSQL安装报告书-命名规约检测报告书.html"

# ------------------------------
# HTML 头部
# ------------------------------
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>PostgreSQL 命名规约检测报告</title>
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:800px}
h2 {color:#1677ff;margin-bottom:20px;text-align:center}
h3 {color:#444;margin-top:25px;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px}
pre {background:#f0f2f5;padding:12px;border-radius:6px;overflow-x:auto;font-family:monospace}
.status-ok {color:green;font-weight:600}
.status-warning {color:orange;font-weight:600}
.status-missing {color:red;font-weight:600}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🎯 PostgreSQL HA 命名规约检测报告</h2>
EOF

# ------------------------------
# 根据 JSON 生成 HTML
# ------------------------------
RESOURCE_TYPES=("Namespace" "StatefulSet" "Service" "PVC" "Pod")

for TYPE in "${RESOURCE_TYPES[@]}"; do
    cat >> "$HTML_FILE" <<EOF
<h3>$TYPE</h3>
EOF

    ITEMS=$(echo "$JSON_DATA" | jq -c ".[] | select(.resource_type==\"$TYPE\")")
    if [ -z "$ITEMS" ]; then
        echo "<div class='status-ok'>✅ 所有 $TYPE 正常</div>" >> "$HTML_FILE"
    else
        echo "$ITEMS" | while read -r item; do
            NAME=$(echo "$item" | jq -r '.name')
            STATUS=$(echo "$item" | jq -r '.status')
            case "$STATUS" in
                "不存在")
                    CLASS="status-missing"
                    ICON="❌"
                    ;;
                "命名不规范"|"Pending")
                    CLASS="status-warning"
                    ICON="⚠️"
                    ;;
                "Running")
                    CLASS="status-ok"
                    ICON="✅"
                    ;;
                *)
                    CLASS="status-warning"
                    ICON="⚠️"
                    ;;
            esac
            echo "<div class='$CLASS'>$ICON $NAME : $STATUS</div>" >> "$HTML_FILE"
        done
    fi
done

# ------------------------------
# HTML Footer
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<div style="margin-top:20px;font-size:12px;color:#888;text-align:center">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>
</div></div>
</body>
</html>
EOF

echo "✅ PostgreSQL HTML 报告生成完成: $HTML_FILE" >&2
