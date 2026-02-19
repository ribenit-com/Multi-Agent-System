#!/bin/bash
# ===================================================
# 企业级主控脚本模板 - GitOps/ArgoCD 版 v2.0
# 功能：
#   - 调用检测脚本生成 JSON
#   - 生成 Summary 表格 & HTML 报告
#   - 异常触发报警/备份脚本
#   - 调用 CreateYAML 脚本生成 GitOps YAML
# ===================================================

set -e

SCRIPT_VERSION="2.0"
echo "🔹 postgres_control.sh v$SCRIPT_VERSION"

MODULE_NAME="$1"
GITOPS_DIR="${2:-./gitops/$MODULE_NAME}"  # 默认输出 GitOps 目录
shift 2
DETECT_SCRIPTS=("$@")

if [ -z "$MODULE_NAME" ] || [ ${#DETECT_SCRIPTS[@]} -eq 0 ]; then
    echo "Usage: $0 <MODULE_NAME> <OUTPUT_DIR> <DETECT_SCRIPT1> [DETECT_SCRIPT2 ...]"
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

        if [ "$ABNORMAL" -eq 0 ]; then COLOR="\033[32m"
        elif [ "$ABNORMAL" -lt "$TOTAL" ]; then COLOR="\033[33m"
        else COLOR="\033[31m"
        fi

        printf "${COLOR}%-15s %-10s %-10s\033[0m\n" "$TYPE" "$TOTAL" "$ABNORMAL"
    done

    # ------------------------------
    # HTML 报告
    # ------------------------------
    ./check_postgres_names_html.sh <<< "$JSON_OUTPUT"

    # ------------------------------
    # 异常触发示例
    # ------------------------------
    POD_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="Pod" and .status!="Running")] | length')
    if [ "$POD_ISSUES" -gt 0 ]; then
        echo -e "\033[31m⚠️ 触发报警脚本：Pod 异常 $POD_ISSUES 个\033[0m"
        # ./alert_script.sh "$JSON_OUTPUT"
    fi

    PVC_ISSUES=$(echo "$JSON_OUTPUT" | jq '[.[] | select(.resource_type=="PVC" and .status!="命名规范")] | length')
    if [ "$PVC_ISSUES" -gt 0 ]; then
        echo -e "\033[33m⚠️ 触发备份脚本：PVC 异常 $PVC_ISSUES 个\033[0m"
        # ./backup_script.sh "$JSON_OUTPUT"
    fi

    # ------------------------------
    # 调用 CreateYAML 脚本
    # ------------------------------
    echo -e "\n🔹 生成 PostgreSQL HA GitOps YAML：$GITOPS_DIR"
    mkdir -p "$GITOPS_DIR"

    # 可通过环境变量控制副本数和 StorageClass
    REPLICA_COUNT="${REPLICA_COUNT:-3}"
    STORAGE_CLASS="${STORAGE_CLASS:-}"

    ./generate_postgres_ha_yaml.sh "$REPLICA_COUNT" "$STORAGE_CLASS" <<< "$JSON_OUTPUT"

done

echo "✅ 主控完成: 模块 = $MODULE_NAME"
