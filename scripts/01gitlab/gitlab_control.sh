#!/bin/bash
# ===================================================
# GitLab HA 控制脚本（详细执行监控 v1.3）
# 功能：
#   - 强制下载最新 JSON / HTML 脚本
#   - 执行 JSON 检测 + 实时日志
#   - 轮询 JSON 输出（倒计时显示）
#   - Pod/PVC/Namespace/Service 异常统计
#   - 生成 HTML 报告
#   - 显示脚本版本号、工作目录
# ===================================================

set -euo pipefail

SCRIPT_VERSION="v1.3"
MODULE_NAME="${1:-GitLab_HA}"
WORK_DIR=$(mktemp -d)
JSON_LOG="$WORK_DIR/json.log"

echo -e "=============================="
echo -e "🔹 执行 GitLab 控制脚本"
echo -e "🔹 版本号: $SCRIPT_VERSION"
echo -e "🔹 工作目录: $WORK_DIR"
echo -e "=============================="

# -------------------------
# 下载脚本函数
# -------------------------
download_script() {
    local url="$1"
    local dest="$2"
    echo -e "\n🔹 强制下载最新脚本: $url"
    curl -sSL "$url" -o "$dest"
    chmod +x "$dest"
}

# -------------------------
# 脚本 URL
# -------------------------
JSON_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_json.sh"
HTML_SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_html.sh"

JSON_SCRIPT="$WORK_DIR/check_gitlab_names_json.sh"
HTML_SCRIPT="$WORK_DIR/check_gitlab_names_html.sh"

download_script "$JSON_SCRIPT_URL" "$JSON_SCRIPT"
download_script "$HTML_SCRIPT_URL" "$HTML_SCRIPT"

# -------------------------
# 临时 JSON 文件
# -------------------------
TMP_JSON="$WORK_DIR/tmp_json_output.json"
> "$TMP_JSON"

# -------------------------
# 执行 JSON 脚本并实时输出
# -------------------------
echo -e "\n🔹 执行 JSON 检测脚本..."
bash "$JSON_SCRIPT" > >(tee -a "$TMP_JSON") 2> >(tee -a "$JSON_LOG" >&2) &
JSON_PID=$!

# -------------------------
# 轮询等待 JSON 文件生成
# -------------------------
MAX_RETRIES=10
COUNT=0

while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -s "$TMP_JSON" ]; then
        echo -e "\n✅ JSON 文件生成成功: $TMP_JSON"
        break
    fi
    ((COUNT++))
    echo -ne "\r🔄 [$COUNT/$MAX_RETRIES] 等待 JSON 文件生成... 3s倒计时 "
    for i in {3..1}; do
        echo -ne "$i "
        sleep 1
    done
done

if [ ! -s "$TMP_JSON" ]; then
    echo -e "\n\033[31m❌ 超时：JSON 文件未生成\033[0m"
    echo "📄 JSON 日志: $JSON_LOG"
    cat "$JSON_LOG"
    exit 1
fi

wait $JSON_PID
EXIT_CODE=$?
[[ $EXIT_CODE -eq 0 ]] || { echo -e "\033[31m❌ JSON 脚本退出码: $EXIT_CODE\033[0m"; exit 1; }

# -------------------------
# JSON 格式检查
# -------------------------
if ! jq empty "$TMP_JSON" 2>/dev/null; then
    echo -e "\033[31m❌ JSON 文件格式错误\033[0m"
    head -n 20 "$TMP_JSON"
    exit 1
fi

# -------------------------
# 即时预览 JSON 前 5 行
# -------------------------
echo -e "\n🔹 JSON 文件预览（前5行）:"
head -n 5 "$TMP_JSON"

# -------------------------
# 异常统计与详细输出
# -------------------------
POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")
NS_ISSUES=$(jq '[.[] | select(.resource_type=="Namespace" and .status!="存在")] | length' < "$TMP_JSON")
SVC_ISSUES=$(jq '[.[] | select(.resource_type=="Service" and .status!="存在")] | length' < "$TMP_JSON")

[[ "$POD_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ Pod异常: $POD_ISSUES 个\033[0m"
[[ "$PVC_ISSUES" -gt 0 ]] && echo -e "\033[33m⚠️ PVC异常: $PVC_ISSUES 个\033[0m"
[[ "$NS_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ Namespace异常: $NS_ISSUES 个\033[0m"
[[ "$SVC_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ Service异常: $SVC_ISSUES 个\033[0m"

# -------------------------
# 生成 HTML 报告
# -------------------------
echo -e "\n🔹 生成 HTML 报告..."
"$HTML_SCRIPT" "$MODULE_NAME" "$TMP_JSON"

# -------------------------
# 清理
# -------------------------
rm -f "$TMP_JSON"
rm -rf "$WORK_DIR"

echo -e "\n✅ GitLab 控制脚本执行完成: 模块=$MODULE_NAME, 版本=$SCRIPT_VERSION"
