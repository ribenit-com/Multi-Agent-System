#!/bin/bash
# ===================================================
# 企业级主控脚本模板
# 功能：
#   - 调用各类检测脚本（JSON 输出）
#   - 根据 JSON 结果动态调度后续脚本
#   - 支持管道式数据传递
# ===================================================

set -e

# ------------------------------
# 支持指定模块和检测脚本
# ------------------------------
MODULE_NAME="$1"
shift
DETECT_SCRIPTS=("$@")  # 后续检测脚本列表

if [ -z "$MODULE_NAME" ] || [ ${#DETECT_SCRIPTS[@]} -eq 0 ]; then
    echo "Usage: $0 <MODULE_NAME> <DETECT_SCRIPT1> [DETECT_SCRIPT2 ...]"
    exit 1
fi

echo "🔹 主控开始: 模块 = $MODULE_NAME"

# ------------------------------
# 执行每个检测脚本
# ------------------------------
for SCRIPT in "${DETECT_SCRIPTS[@]}"; do
    if [ ! -x "$SCRIPT" ]; then
        echo "⚠️ 脚本不可执行: $SCRIPT, 跳过"
        continue
    fi

    echo -e "\n🔹 调用检测脚本: $SCRIPT"

    # 脚本输出 JSON，通过管道传给后续处理脚本
    JSON_OUTPUT=$("$SCRIPT" | tee /dev/tty)

    # ------------------------------
    # 根据 JSON 结果动态调度其他动作
    # ------------------------------
    # 示例：Pod 异常 → 调用报警脚本
    POD_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length')
    if [ "$POD_ISSUES" -gt 0 ]; then
        echo -e "\033[31m⚠️ 检测到 $POD_ISSUES 个 Pod 异常，触发报警脚本\033[0m"
        # ./alert_script.sh "$JSON_OUTPUT"
    fi

    # 示例：PVC 异常 → 调用备份脚本
    PVC_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length')
    if [ "$PVC_ISSUES" -gt 0 ]; then
        echo -e "\033[33m⚠️ 检测到 $PVC_ISSUES 个 PVC 异常，触发备份脚本\033[0m"
        # ./backup_script.sh "$JSON_OUTPUT"
    fi

    # 示例：生成 HTML 报告
    ./check_postgres_names_html.sh <<< "$JSON_OUTPUT"
done

echo "✅ 主控完成: 模块 = $MODULE_NAME"
