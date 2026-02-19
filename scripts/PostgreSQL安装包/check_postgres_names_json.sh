#!/bin/bash
# ===================================================
# check_postgres_names_json.sh v1.1 独立执行版
# 功能：
#   - 检测 PostgreSQL HA 相关资源
#   - 输出标准化 JSON
# ===================================================

set -e

# -------------------------------
# 配置
# -------------------------------
NAMESPACE_STANDARD="ns-postgres-ha"
STATEFULSET_STANDARD="sts-postgres-ha"
SERVICE_PRIMARY_STANDARD="svc-postgres-primary"
SERVICE_REPLICA_STANDARD="svc-postgres-replica"
PVC_PATTERN="pvc-postgres-ha-"
APP_LABEL="postgres-ha"
APP_NAME="PostgreSQL"

# -------------------------------
# 获取资源信息
# -------------------------------
EXIST_NAMESPACE=$(kubectl get ns 2>/dev/null | awk '{print $1}' | grep "^$NAMESPACE_STANDARD$" || echo "")
STS_LIST=$(kubectl -n "$NAMESPACE_STANDARD" get sts -l app="$APP_LABEL" -o name 2>/dev/null || echo "")
SERVICE_LIST=$(kubectl -n "$NAMESPACE_STANDARD" get svc -l app="$APP_LABEL" -o name 2>/dev/null || echo "")
PVC_LIST=$(kubectl -n "$NAMESPACE_STANDARD" get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
POD_STATUS=$(kubectl -n "$NAMESPACE_STANDARD" get pods -l app="$APP_LABEL" -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers 2>/dev/null || echo "")

json_entries=()

# -------------------------------
# Namespace
# -------------------------------
if [[ -z "$EXIST_NAMESPACE" ]]; then
    json_entries+=("{\"resource_type\":\"Namespace\",\"name\":\"$NAMESPACE_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
fi

# -------------------------------
# StatefulSet
# -------------------------------
if [[ -z "$STS_LIST" ]]; then
    json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$STATEFULSET_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for sts in $STS_LIST; do
        NAME=$(echo "$sts" | awk -F'/' '{print $2}')
        if [[ "$NAME" != "$STATEFULSET_STANDARD" ]]; then
            json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$NAME\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
        fi
    done
fi

# -------------------------------
# Service
# -------------------------------
SERVICES_TO_CHECK=("$SERVICE_PRIMARY_STANDARD" "$SERVICE_REPLICA_STANDARD")
for svc in "${SERVICES_TO_CHECK[@]}"; do
    if ! echo "$SERVICE_LIST" | grep -q "/$svc"; then
        json_entries+=("{\"resource_type\":\"Service\",\"name\":\"$svc\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
    fi
done

# -------------------------------
# PVC
# -------------------------------
if [[ -z "$PVC_LIST" ]]; then
    json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"${PVC_PATTERN}*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for pvc in $PVC_LIST; do
        if [[ "$pvc" != ${PVC_PATTERN}* ]]; then
            json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"$pvc\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
        fi
    done
fi

# -------------------------------
# Pod
# -------------------------------
if [[ -z "$POD_STATUS" ]]; then
    json_entries+=("{\"resource_type\":\"Pod\",\"name\":\"*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    while read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $2}')
        if [[ "$STATUS" != "Running" ]]; then
            json_entries+=("{\"resource_type\":\"Pod\",\"name\":\"$POD_NAME\",\"status\":\"$STATUS\",\"app\":\"$APP_NAME\"}")
        fi
    done <<< "$POD_STATUS"
fi

# -------------------------------
# 输出标准化 JSON
# -------------------------------
if [ ${#json_entries[@]} -eq 0 ]; then
    echo "[]"
else
    echo "["
    for i in "${!json_entries[@]}"; do
        if [[ $i -lt $((${#json_entries[@]} - 1)) ]]; then
            echo "  ${json_entries[$i]},"
        else
            echo "  ${json_entries[$i]}"
        fi
    done
    echo "]"
fi
