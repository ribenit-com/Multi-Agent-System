#!/bin/bash
set -euo pipefail

#########################################
# GitLab 控制脚本 v1.9
# 功能：强制下载最新 JSON/HTML 检测脚本
#       执行 JSON 检测
#       打印详细异常
#       生成 HTML 报告
#########################################

SCRIPT_VERSION="v1.9"
MODULE_NAME="${1:-GitLab_HA}"
WORK_DIR=$(mktemp -d)
TMP_JSON="$WORK_DIR/tmp_json_output.json"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

echo "=============================="
echo "🔹 执行 GitLab 控制脚本"
echo "🔹 版本号: $SCRIPT_VERSION"
echo "🔹 工作目录: $WORK_DIR"
echo "=============================="

#########################################
# 强制下载脚本函数
#########################################
download_script() {
    local url="$1"
    local dest="$2"
    echo "🔹 下载最新脚本: $url"
    echo "🔹 执行: curl -sSL $url -o $dest"
    curl -sSL "$url" -o "$dest"
    chmod +x "$dest"
}

JSON_SCRIPT="$WORK_DIR/check_gitlab_names_json.sh"
HTML_SCRIPT="$WORK_DIR/check_gitlab_names_html.sh"

download_script "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_json.sh" "$JSON_SCRIPT"
download_script "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/01gitlab/check_gitlab_names_html.sh" "$HTML_SCRIPT"

#########################################
# 执行 JSON 脚本并轮询生成文件
#########################################
echo -e "\n🔹 执行 JSON 检测脚本..."
bash "$JSON_SCRIPT" > "$TMP_JSON" 2> "$WORK_DIR/json_error.log" || echo "⚠️ JSON 脚本执行报错，检查 $WORK_DIR/json_error.log"

# 等待 JSON 文件生成（轮询）
MAX_RETRIES=10
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
    if [ -s "$TMP_JSON" ]; then
        echo "✅ JSON 文件生成成功: $TMP_JSON"
        break
    fi
    ((COUNT++))
    echo "🔄 [$COUNT/$MAX_RETRIES] JSON 未生成，等待 3 秒..."
    sleep 3
done

if [ ! -s "$TMP_JSON" ]; then
    echo "❌ 超时：JSON 文件未生成"
    cat "$WORK_DIR/json_error.log"
    exit 1
fi

#########################################
# 检查 JSON 格式
#########################################
echo -e "\n🔹 检查 JSON 格式..."
if jq empty "$TMP_JSON" 2>/dev/null; then
    echo "✅ JSON 文件格式合法"
else
    echo "❌ JSON 文件格式错误"
    cat "$TMP_JSON"
    exit 1
fi

echo -e "\n🔹 JSON 文件预览（前5行）:"
head -n 5 "$TMP_JSON"

#########################################
# 异常统计并打印详细内容
#########################################
echo -e "\n🔹 检查 Pod/PVC/Namespace/Service 异常..."
POD_ENTRIES=$(jq '.[] | select(.resource_type=="Pod" and .status!="Running")' < "$TMP_JSON")
PVC_ENTRIES=$(jq '.[] | select(.resource_type=="PVC" and .status!="命名规范")' < "$TMP_JSON")
NS_ENTRIES=$(jq '.[] | select(.resource_type=="Namespace" and .status!="存在")' < "$TMP_JSON")
SVC_ENTRIES=$(jq '.[] | select(.resource_type=="Service" and .status!="存在")' < "$TMP_JSON")

[[ $(echo "$POD_ENTRIES" | jq -s 'length') -gt 0 ]] && echo -e "\033[31m⚠️ Pod异常:\033[0m" && echo "$POD_ENTRIES" | jq '.'
[[ $(echo "$PVC_ENTRIES" | jq -s 'length') -gt 0 ]] && echo -e "\033[33m⚠️ PVC异常:\033[0m" && echo "$PVC_ENTRIES" | jq '.'
[[ $(echo "$NS_ENTRIES" | jq -s 'length') -gt 0 ]] && echo -e "\033[31m⚠️ Namespace异常:\033[0m" && echo "$NS_ENTRIES" | jq '.'
[[ $(echo "$SVC_ENTRIES" | jq -s 'length') -gt 0 ]] && echo -e "\033[31m⚠️ Service异常:\033[0m" && echo "$SVC_ENTRIES" | jq '.'

#########################################
# 生成 HTML 报告
#########################################
echo -e "\n🔹 生成 HTML 报告..."
"$HTML_SCRIPT" "$MODULE_NAME" "$TMP_JSON"
echo "✅ HTML 报告生成完成"

#########################################
# 清理临时文件
#########################################
echo -e "\n🔹 清理临时文件..."
rm -rf "$WORK_DIR"

echo -e "\n✅ GitLab 控制脚本执行完成: 模块=$MODULE_NAME, 版本=$SCRIPT_VERSION"
