#!/bin/bash
# ===================================================
# PostgreSQL HA 主控脚本（优化版）
# 功能：
#   - 调用 JSON 检测脚本
#   - 根据结果可扩展调度
#   - 生成 HTML 报告
# ===================================================

set -euo pipefail

MODULE_NAME="$1"
shift
DETECT_SCRIPTS=("$@")

if [[ -z "$MODULE_NAME" || ${#DETECT_SCRIPTS[@]} -eq 0 ]]; then
    echo "Usage: $0 <MODULE_NAME> <DETECT_SCRIPT1> [DETECT_SCRIPT2 ...]"
    exit 1
fi

echo "🔹 主控开始: 模块 = $MODULE_NAME"

for SCRIPT in "${DETECT_SCRIPTS[@]}"; do
    if [[ ! -x "$SCRIPT" ]]; then
        echo "⚠️ 脚本不可执行: $SCRIPT, 跳过"
        continue
    fi

    echo -e "\n🔹 调用检测脚本: $SCRIPT"

    # 使用临时文件传 JSON，避免 shell 参数长度限制
    TMP_JSON=$(mktemp)
    "$SCRIPT" > "$TMP_JSON"

    # 检查 Pod/PVC 异常
    POD_ISSUES=$(jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length' < "$TMP_JSON")
    PVC_ISSUES=$(jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length' < "$TMP_JSON")

    [[ "$POD_ISSUES" -gt 0 ]] && echo -e "\033[31m⚠️ 检测到 $POD_ISSUES 个 Pod 异常\033[0m"
    [[ "$PVC_ISSUES" -gt 0 ]] && echo -e "\033[33m⚠️ 检测到 $PVC_ISSUES 个 PVC 异常\033[0m"

    # 生成 HTML 报告
    ./check_postgres_names_html.sh "$MODULE_NAME" "$TMP_JSON"

    rm -f "$TMP_JSON"
done

echo "✅ 主控完成: 模块 = $MODULE_NAME"
