#!/bin/bash
# ===================================================
# HTML 报告生成脚本（PostgreSQL HA） - 修正版 2026-02-19 v1.1
# 功能：接收 JSON（文件或 stdin），生成 HTML 报告
# ===================================================

set -e

echo "🔹 check_postgres_names_html.sh v1.1"

# -------------------------------
# JSON 输入处理
# -------------------------------
if [ -t 0 ] && [ -z "$1" ]; then
    echo "Usage: $0 <JSON_FILE> 或通过管道传入 JSON"
    exit 1
fi

if [ -t 0 ]; then
    JSON_INPUT="$1"
    JSON_DATA=$(cat "$JSON_INPUT")
else
    JSON_DATA=$(cat)   # 从管道读取
fi

# -------------------------------
# 输出目录和文件
# -------------------------------
BASE_DIR="/mnt/truenas"
REPORT_DIR="$BASE_DIR/PostgreSQL安装报告书"
mkdir -p "$REPORT_DIR"

MODULE_NAME="PostgreSQL_HA"
DESCRIPTION="命名规约检测报告"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

HTML_FILE="$REPORT_DIR/${MODULE_NAME}_${DESCRIPTION}_$TIMESTAMP.html"
LATEST_FILE="$REPORT_DIR/latest.html"

# -------------------------------
# HTML 头部
# -------------------------------
cat > "$HTML_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>PostgreSQL_HA 命名规约检测报告</title>
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:800px}
h2 {color:#1677ff;margin-bottom:20px;text-align:center}
h3 {color:#444;margin-top:25px;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px}
.status-ok {color:green;font-weight:600}
.status-warning {color:orange;font-weight:600}
.status-missing {color:red;font-weight:600}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🎯 PostgreSQL_HA 命名规约检测报告</h2>
EOF

# -------------------------------
# 遍历资源类型
# -------------------------------
RESOURCE_TYPES=("Namespace" "StatefulSet" "Service" "PVC" "Pod")

for TYPE in "${RESOURCE_TYPES[@]}"; do
    echo "<h3>$TYPE</h3>" >> "$HTML_FILE"
    ITEM_COUNT=$(echo "$JSON_DATA" | jq "[.[] | select(.resource_type==\"$TYPE\") ] | length")
    if [ "$ITEM_COUNT" -eq 0 ]; then
        echo "<div class='status-ok'>✅ 所有 $TYPE 正常</div>" >> "$HTML_FILE"
    else
        echo "$JSON_DATA" | jq -c ".[] | select(.resource_type==\"$TYPE\")" | while read -r item; do
            NAME=$(echo "$item" | jq -r '.name')
            STATUS=$(echo "$item" | jq -r '.status')
            case "$STATUS" in
                "不存在") CLASS="status-missing"; ICON="❌";;
                "命名不规范"|"Pending") CLASS="status-warning"; ICON="⚠️";;
                "Running") CLASS="status-ok"; ICON="✅";;
                *) CLASS="status-warning"; ICON="⚠️";;
            esac
            echo "<div class='$CLASS'>$ICON $NAME : $STATUS</div>" >> "$HTML_FILE"
        done
    fi
done

# -------------------------------
# Footer
# -------------------------------
cat >> "$HTML_FILE" <<EOF
<div style="margin-top:20px;font-size:12px;color:#888;text-align:center">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>
</div></div>
</body>
</html>
EOF

# -------------------------------
# 创建最新报告软链接
# -------------------------------
ln -sf "$(basename "$HTML_FILE")" "$LATEST_FILE"

echo "✅ HTML 报告生成完成: $HTML_FILE"
echo "🔗 最新报告链接: $LATEST_FILE"
