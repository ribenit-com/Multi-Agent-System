#!/bin/bash
# ===================================================
# GitLab HA 控制脚本（优化版 v1.1）
# 最终修改日期：2026-02-21
# 功能：
#   - 每次下载最新 JSON 检测脚本和 HTML 报告生成脚本
#   - 强制下载，每次都会覆盖本地脚本
#   - 执行 JSON 检测
#   - 轮询等待 JSON 文件生成（3 秒倒计时）
#   - 实时显示 JSON 执行日志
#   - Pod / PVC / Service / Namespace 异常统计
#   - 生成 HTML 报告
# ===================================================

set -euo pipefail

SCRIPT_VERSION="v1.1"
MODULE_NAME="${1:-GitLab_HA}"
WORK_DIR=$(mktemp -d)
echo -e "=============================="
echo -e "🔹 执行 GitLab 控制脚本"
echo -e "🔹 版本号: $SCRIPT_VERSION"
echo -e "🔹 工作目录: $WORK_DIR"
echo -e "=============================="

# -------------------------
# 下载远程脚本函数
# -------------------------
download_script() {
    local url="$1"
    local dest="$2"
    echo -e "🔹 强制下载最新脚本: $url"
    http_status=$(curl -s -o "$dest" -w "%{http_code}" "$url")
    if [[ "$http_status" -ne 200 ]]; then
        echo -e "\033[31m❌ 下载失败 (HTTP $http_status)：$url\033[0m"
        exit 1
    fi
    chmod +x "$dest"
}

# -------------------------
# 脚本 URL
# -------------------------
JSON_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_json.sh"
HTML_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_html.sh"

JSON_SCRIPT="$WORK_DIR/check_gitlab_names_json.sh"
HTML_SCRIPT="$WORK_DIR/check_gitlab_names_html.sh"

# -------------------------
# 每次强制下载最新脚本
# -------------------------
download_script "$JSON_SCRIPT_URL" "$JSON_SCRIPT"
download_script "$HTML_SCRIPT_URL" "$HTML_SCRIPT"

# -------------------------
# 临时 JSON 文件
# -------------------------
TMP_JSON="$WORK_DIR/tmp_json_output.json"
JSON_LOG="$WORK_DIR/json_error.log"

# -------------------------
# 执行 JSON 脚本并轮询等待输出（带 3 秒倒计时）
# -------------------------
echo -e "\n🔹 执行 JSON 检测脚本..."
bash "$JSON_SCRIPT" > "$TMP_JSON" 2> "$JSON_LOG" &
JSON_PID=$!

MAX_RETRIES=10
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -s "$TMP_JSON" ]; then
        echo -e "\n✅ 成功生成 JSON 文件：$TMP_JSON"
        break
    fi
    ((COUNT++))
    echo -ne "\r🔄 [$COUNT/$MAX_RETRIES] JSON 文件未生成，等待 3 秒..."
    for i in {3..1}; do
        echo -ne " $i..."
        sleep 1
    done
done

# 检查轮询结果
if [ ! -s "$TMP_JSON" ]; then
    echo -e "\n\033[31m❌ 超时：$JSON_SCRIPT 未生成 JSON 文件。\033[0m"
    echo "📄 查看 JSON 执行日志：$JSON_LOG"
    cat "$JSON_LOG"
    exit 1
fi

# 等待脚本执行完成并获取退出码
wait $JSON_PID
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\033[31m❌ JSON 检测脚本执行失败 (退出码 $EXIT_CODE)\033[0m"
    echo "📄 实时 JSON 执行日志：$JSON_LOG"
    cat "$JSON_LOG"
    exit 1
fi

# -------------------------
# 检查 JSON 格式
# -------------------------
if ! jq empty "$TMP_JSON" 2>/dev/null; then
    echo -e "\033[31m❌ 输出不是合法 JSON，请检查脚本或网络下载是否正确\033[0m"
    cat "$TMP_JSON"
    exit 1
fi

# -------------------------
# Pod / PVC / Service / Namespace 异常统计
# -------------------------
POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")
NS_ISSUES=$(jq '[.[] | select(.resource_type=="Namespace" and .status!="存在")] | length' < "$TMP_JSON")
SVC_ISSUES=$(jq '[.[] | select(.resource_type=="Service" and .status!="存在")] | length' < "$TMP_JSON")

[[ "$POD_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ 检测到 $POD_ISSUES 个 Pod 异常\033[0m"
[[ "$PVC_ISSUES" -gt 0 ]] && echo -e "\033[33m⚠️ 检测到 $PVC_ISSUES 个 PVC 异常\033[0m"
[[ "$NS_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ 检测到 $NS_ISSUES 个 Namespace 异常\033[0m"
[[ "$SVC_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ 检测到 $SVC_ISSUES 个 Service 异常\033[0m"

# -------------------------
# 生成 HTML 报告
# -------------------------
echo -e "\n🔹 生成 HTML 报告..."
"$HTML_SCRIPT" "$MODULE_NAME" "$TMP_JSON"

# -------------------------
# 清理临时文件
# -------------------------
rm -f "$TMP_JSON"
rm -rf "$WORK_DIR"

echo -e "\n✅ GitLab 控制脚本执行完成: 模块 = $MODULE_NAME, 版本 = $SCRIPT_VERSION"
