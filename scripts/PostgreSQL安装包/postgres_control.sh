#!/bin/bash
# ===================================================
# 企业级主控脚本模板
# 功能：
#   - 调用各类检测脚本（输出 JSON）
#   - 根据 JSON 结果动态调度后续脚本
#   - 支持管道式数据传递
#   - 生成 Summary 表格
# ===================================================

set -e

MODULE_NAME="$1"
shift
DETECT_SCRIPTS=("$@")

if [ -z "$MODULE_NAME" ] || [ ${#DETECT_SCRIPTS[@]} -eq 0 ]; then
    echo "Usage: $0 <MODULE_NAME> <DETECT_SCRIPT1> [DETECT_SCRIPT2 ...]"
    exit 1
fi

echo "🔹 主控开始: 模块 = $MODULE_NAME"

for SCRIPT in "${DETECT_SCRIPTS[@]}"; do
    if [ ! -x "$SCRIPT" ]; then
        echo "⚠️ 脚本不可执行: $SCRIPT, 跳过"
        continue
    fi

    echo -e "\n🔹 调用检测脚本: $SCRIPT"

    # JSON 输出管道式传递，实时显示
    JSON_OUTPUT=$("$SCRIPT" | tee /dev/tty)

    # ------------------------------
    # Summary 表格统计
    # ------------------------------
    RESOURCE_TYPES=("Namespace" "StatefulSet" "Service" "PVC" "Pod")
    echo -e "\n📊 Summary："
    printf "%-15s %-10s %-10s\n" "资源类型" "总数" "异常数"
    echo "--------------------------------------"

    for TYPE in "${RESOURCE_TYPES[@]}"; do
        TOTAL=$(echo "$JSON_OUTPUT" | jq "[.[] | select(.resource_type==\"$TYPE\")] | length")
        if [ "$TYPE" == "Pod" ]; then
            ABNORMAL=$(echo "$JSON_OUTPUT" | jq "[.[] | select(.resource_type==\"$TYPE\" and .status != \"Running\")] | length")
        else
            ABNORMAL=$TOTAL
        fi

        if [ "$ABNORMAL" -eq 0 ]; then COLOR="\033[32m"       # 绿色
        elif [ "$ABNORMAL" -lt "$TOTAL" ]; then COLOR="\033[33m" # 橙色
        else COLOR="\033[31m"                                 # 红色
        fi

        printf "${COLOR}%-15s %-10s %-10s\033[0m\n" "$TYPE" "$TOTAL" "$ABNORMAL"
    done

    # ------------------------------
    # 动态调度后续脚本
    # ------------------------------

    # HTML 报告
    ./check_postgres_names_html.sh <<< "$JSON_OUTPUT"

    # 示例：Pod 异常触发报警脚本
    POD_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length')
    if [ "$POD_ISSUES" -gt 0 ]; then
        echo -e "\033[31m⚠️ 触发报警脚本：Pod 异常 $POD_ISSUES 个\033[0m"
        # ./alert_script.sh "$JSON_OUTPUT"
    fi

    # 示例：PVC 异常触发备份脚本
    PVC_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length')
    if [ "$PVC_ISSUES" -gt 0 ]; then
        echo -e "\033[33m⚠️ 触发备份脚本：PVC 异常 $PVC_ISSUES 个\033[0m"
        # ./backup_script.sh "$JSON_OUTPUT"
    fi
done

echo "✅ 主控完成: 模块 = $MODULE_NAME"
