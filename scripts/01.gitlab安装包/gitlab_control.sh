#!/bin/bash
# ===================================================
# GitLab PostgreSQL HA 控制脚本
# 功能：
#   - 下载 JSON 检测脚本和 HTML 报告生成脚本
#   - 执行检测
#   - 生成 HTML 报告
# ===================================================

set -euo pipefail

MODULE_NAME="${1:-PostgreSQL_HA}"
WORK_DIR=$(mktemp -d)
echo "🔹 工作目录: $WORK_DIR"

# -------------------------
# 下载远程脚本
# -------------------------
JSON_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_json.sh"
HTML_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/PostgreSQL%E5%AE%89%E8%A3%85%E5%8C%85/check_postgres_names_html.sh"

JSON_SCRIPT="$WORK_DIR/check_postgres_names_json.sh"
HTML_SCRIPT="$WORK_DIR/check_postgres_names_html.sh"

echo "🔹 下载 JSON 检测脚本..."
curl -fsSL "$JSON_SCRIPT_URL" -o "$JSON_SCRIPT"
chmod +x "$JSON_SCRIPT"

echo "🔹 下载 HTML 报告生成脚本..."
curl -fsSL "$HTML_SCRIPT_URL" -o "$HTML_SCRIPT"
chmod +x "$HTML_SCRIPT"

# -------------------------
# 临时 JSON 文件
# -------------------------
TMP_JSON=$(mktemp)

# -------------------------
# 执行 JSON 检测脚本
# -------------------------
echo "🔹 执行 JSON 检测脚本..."
"$JSON_SCRIPT" > "$TMP_JSON"

# -------------------------
# 检查异常
# -------------------------
POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")

[[ "$POD_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ 检测到 $POD_ISSUES 个 Pod 异常\033[0m"
[[ "$PVC_ISSUES" -gt 0 ]] && echo -e "\033[33m⚠️ 检测到 $PVC_ISSUES 个 PVC 异常\033[0m"

# -------------------------
# 生成 HTML 报告
# -------------------------
echo "🔹 生成 HTML 报告..."
"$HTML_SCRIPT" "$MODULE_NAME" "$TMP_JSON"

# -------------------------
# 清理临时文件
# -------------------------
rm -f "$TMP_JSON"
rm -rf "$WORK_DIR"

echo "✅ GitLab 控制脚本执行完成: 模块 = $MODULE_NAME"
