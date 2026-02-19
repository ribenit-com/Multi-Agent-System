#!/bin/bash
# ===================================================
# PostgreSQL 模块主控脚本（企业级全流程版 + Summary 表格）
# 功能：
#   - 调用 JSON 检测脚本
#   - 实时显示 JSON 输出
#   - 显示 Summary 表格（每类资源总数 / 异常数量）
#   - 调用 HTML 脚本生成报告（带时间戳 + latest.html）
# ===================================================

set -e

echo "🔹 Step 1: 生成 PostgreSQL JSON 检测结果..."

# ------------------------------
# JSON 临时变量，用于统计 Summary
# ------------------------------
JSON_DATA=$(./check_postgres_names_json.sh | tee >( ./check_postgres_names_html.sh /dev/stdin ))

# ------------------------------
# Summary 表格统计
# ------------------------------
RESOURCE_TYPES=("Namespace" "StatefulSet" "Service" "PVC" "Pod")

echo -e "\n📊 PostgreSQL HA 检测 Summary："
printf "%-15s %-10s %-10s\n" "资源类型" "总数" "异常数"
echo "--------------------------------------"

for TYPE in "${RESOURCE_TYPES[@]}"; do
    TOTAL=$(echo "$JSON_DATA" | jq "[.[] | select(.resource_type==\"$TYPE\") ] | length")
    # 异常数 = 除了 Running / 空数组
    if [ "$TYPE" == "Pod" ]; then
        ABNORMAL=$(echo "$JSON_DATA" | jq "[.[] | select(.resource_type==\"$TYPE\" and .status != \"Running\") ] | length")
    else
        ABNORMAL=$TOTAL
        TOTAL=$(echo "$JSON_DATA" | jq "[.[] | select(.resource_type==\"$TYPE\") ] | length + $(kubectl get $TYPE -A --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo 0)")
    fi

    if [ "$ABNORMAL" -eq 0 ]; then
        COLOR="\033[32m"  # 绿色
    elif [ "$ABNORMAL" -lt "$TOTAL" ]; then
        COLOR="\033[33m"  # 橙色
    else
        COLOR="\033[31m"  # 红色
    fi

    printf "${COLOR}%-15s %-10s %-10s\033[0m\n" "$TYPE" "$TOTAL" "$ABNORMAL"
done

echo -e "\n🔹 Step 2: HTML 报告生成完成（含最新报告快捷链接 latest.html）"
