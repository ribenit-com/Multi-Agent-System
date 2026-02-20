#!/bin/bash
# ===================================================
# GitLab HA 控制脚本（改进版）
# 功能：
#   - 下载 JSON 检测脚本和 HTML 报告生成脚本
#   - 执行检测
#   - 生成 HTML 报告
#   - 下载校验 + JSON 格式检查
# ===================================================

set -euo pipefail

MODULE_NAME="${1:-GitLab_HA}"
WORK_DIR=$(mktemp -d)
echo "🔹 工作目录: $WORK_DIR"

# -------------------------
# 下载远程脚本函数
# -------------------------
download_script() {
    local url="$1"
    local dest="$2"
    echo "🔹 下载脚本: $url"
    http_status=$(curl -s -o "$dest" -w "%{http_code}" "$url")
    if [[ "$http_status" -ne 200 ]]; then
        echo -e "\033[31m❌ 下载失败 (HTTP $http_status)：$url\033[0m"
        exit 1
    fi
    chmod +x "$dest"
}

# -------------------------
# 脚本 URL（改为英文路径）
# -------------------------
JSON_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_json.sh"
HTML_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System//main/scripts/01gitlab/check_gitlab_names_html.sh"

JSON_SCRIPT="$WORK_DIR/check_gitlab_names_json.sh"
HTML_SCRIPT="$WORK_DIR/check_gitlab_names_html.sh"

# -------------------------
# 下载脚本
# -------------------------
download_script "$JSON_SCRIPT_URL" "$JSON_SCRIPT"
download_script "$HTML_SCRIPT_URL" "$HTML_SCRIPT"

# -------------------------
# 临时 JSON 文件
# -------------------------
TMP_JSON=$(mktemp)

# -------------------------
# 执行 JSON 脚本并检查输出
# -------------------------
echo "🔹 执行 JSON 检测脚本..."
set +e
bash "$JSON_SCRIPT" > "$TMP_JSON" 2> "$WORK_DIR/json_error.log"
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\033[31m❌ JSON 检测脚本执行失败，查看日志：$WORK_DIR/json_error.log\033[0m"
    cat "$WORK_DIR/json_error.log"
    exit 1
fi

# 检查 JSON 格式
if ! jq empty "$TMP_JSON" 2>/dev/null; then
    echo -e "\033[31m❌ 输出不是合法 JSON，请检查脚本或网络下载是否正确\033[0m"
    echo "查看文件内容：$TMP_JSON"
    cat "$TMP_JSON"
    exit 1
fi

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
