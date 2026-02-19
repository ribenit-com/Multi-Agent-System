#!/bin/bash
# ===================================================
# JSON 检测脚本（PostgreSQL HA）
# 输出标准化 JSON
# ===================================================

set -e

NAMESPACE_STANDARD="ns-postgres-ha"
STATEFULSET_STANDARD="sts-postgres-ha"
SERVICE_PRIMARY_STANDARD="svc-postgres-primary"
SERVICE_REPLICA_STANDARD="svc-postgres-replica"
PVC_PATTERN="pvc-postgres-ha-"
APP_LABEL="postgres-ha"
APP_NAME="PostgreSQL"

EXIST_NAMESPACE=$(kubectl get ns | awk '{print $1}' | grep "^$NAMESPACE_STANDARD$" || echo "")
STS_LIST=$(kubectl -n $NAMESPACE_STANDARD get sts -l app=$APP_LABEL -o name 2>/dev/null || echo "")
SERVICE_LIST=$(kubectl -n $NAMESPACE_STANDARD get svc -l app=$APP_LABEL -o name 2>/dev/null || echo "")
PVC_LIST=$(kubectl -n $NAMESPACE_STANDARD get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
POD_STATUS=$(kubectl -n $NAMESPACE_STANDARD get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers 2>/dev/null || echo "")

json_entries=()

# Namespace
if [[ -z "$EXIST_NAMESPACE" ]]; then
    json_entries+=("{\"resource_type\":\"Namespace\",\"name\":\"$NAMESPACE_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
fi

# StatefulSet
if [[ -z "$STS_LIST" ]]; then
    json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$STATEFULSET_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for sts in $STS_LIST; do
        NAME=$(echo $sts | awk -F'/' '{print $2}')
        [[ "$NAME" != "$STATEFULSET_STANDARD" ]] && json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$NAME\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
    done
fi

# Service
SERVICES_TO_CHECK=("$SERVICE_PRIMARY_STANDARD" "$SERVICE_REPLICA_STANDARD")
for svc in "${SERVICES_TO_CHECK[@]}"; do
    ! echo "$SERVICE_LIST" | grep -q "/$svc" && json_entries+=("{\"resource_type\":\"Service\",\"name\":\"$svc\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
done

# PVC
if [[ -z "$PVC_LIST" ]]; then
    json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"$PVC_PATTERN*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for pvc in $PVC_LIST; do
        [[ "$pvc" != ${PVC_PATTERN}* ]] && json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"$pvc\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
    done
fi

# Pod
if [[ -z "$POD_STATUS" ]]; then
    json_entries+=("{\"resource_type\":\"Pod\",\"name\":\"*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    while read -r line; do
        POD_NAME=$(echo $line | awk '{print $1}')
        STATUS=$(echo $line | awk '{print $2}')
        [[ "$STATUS" != "Running" ]] && json_entries+=("{\"resource_type\":\"Pod\",\"name\":\"$POD_NAME\",\"status\":\"$STATUS\",\"app\":\"$APP_NAME\"}")
    done <<< "$POD_STATUS"
fi

# 输出 JSON
if [ ${#json_entries[@]} -eq 0 ]; then
    echo "[]"
else
    printf "[\n%s\n]\n" "$(IFS=,; echo "${json_entries[*]}")"
fi
