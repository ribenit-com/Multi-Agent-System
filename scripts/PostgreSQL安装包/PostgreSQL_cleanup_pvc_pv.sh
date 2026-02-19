#!/bin/bash
# ===================================================
# 脚本名称: detect_postgresql_naming_full.sh
# 功能: 检测 PostgreSQL HA 命名规范
#       - 生成 HTML 报告
#       - 返回 JSON 数据供主控脚本读取
#       - 不创建/删除资源
# ===================================================

set -e

# ------------------------------
# 标准化命名规范
# ------------------------------
NAMESPACE_STANDARD="ns-postgres-ha"
STATEFULSET_STANDARD="sts-postgres-ha"
SERVICE_PRIMARY_STANDARD="svc-postgres-primary"
SERVICE_REPLICA_STANDARD="svc-postgres-replica"
PVC_PATTERN="pvc-postgres-ha-"
APP_LABEL="postgres-ha"
APP_NAME="PostgreSQL"

# ------------------------------
# 报告目录
# ------------------------------
BASE_DIR="/mnt/truenas"
REPORT_DIR="$BASE_DIR/PostgreSQL安装报告书"
mkdir -p "$REPORT_DIR"
HTML_FILE="$REPORT_DIR/PostgreSQL安装报告书-命名规约检测报告书.html"
JSON_FILE="$REPORT_DIR/PostgreSQL命名规约检测报告书.json"

# ------------------------------
# 获取资源信息
# ------------------------------
EXIST_NAMESPACE=$(kubectl get ns | awk '{print $1}' | grep "^$NAMESPACE_STANDARD$" || echo "")
STS_LIST=$(kubectl -n $NAMESPACE_STANDARD get sts -l app=$APP_LABEL -o name 2>/dev/null || echo "")
SERVICE_LIST=$(kubectl -n $NAMESPACE_STANDARD get svc -l app=$APP_LABEL -o name 2>/dev/null || echo "")
PVC_LIST=$(kubectl -n $NAMESPACE_STANDARD get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
POD_STATUS=$(kubectl -n $NAMESPACE_STANDARD get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers 2>/dev/null || echo "")

# ------------------------------
# 初始化 JSON 数组
# ------------------------------
json_entries=()

# ------------------------------
# HTML 头部
# ------------------------------
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>PostgreSQL 命名规约检测报告</title>
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:800px}
h2 {color:#1677ff;margin-bottom:20px;text-align:center}
h3 {color:#444;margin-top:25px;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px}
pre {background:#f0f2f5;padding:12px;border-radius:6px;overflow-x:auto;font-family:monospace}
.status-ok {color:green;font-weight:600}
.status-warning {color:orange;font-weight:600}
.status-missing {color:red;font-weight:600}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🎯 PostgreSQL HA 命名规约检测报告</h2>
EOF

# ------------------------------
# 检测 Namespace
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<h3>Namespace</h3>
EOF
if [[ -z "$EXIST_NAMESPACE" ]]; then
    echo "<div class='status-missing'>❌ Namespace $NAMESPACE_STANDARD 不存在，需要创建</div>" >> "$HTML_FILE"
    json_entries+=("{\"resource_type\":\"Namespace\",\"name\":\"$NAMESPACE_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    echo "<div class='status-ok'>✅ Namespace $NAMESPACE_STANDARD 已存在</div>" >> "$HTML_FILE"
fi

# ------------------------------
# 检测 StatefulSet
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<h3>StatefulSet</h3>
EOF
if [[ -z "$STS_LIST" ]]; then
    echo "<div class='status-missing'>❌ StatefulSet $STATEFULSET_STANDARD 不存在，需要创建</div>" >> "$HTML_FILE"
    json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$STATEFULSET_STANDARD\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for sts in $STS_LIST; do
        NAME=$(echo $sts | awk -F'/' '{print $2}')
        if [[ "$NAME" == "$STATEFULSET_STANDARD" ]]; then
            echo "<div class='status-ok'>✅ StatefulSet $NAME 命名规范正确</div>" >> "$HTML_FILE"
        else
            echo "<div class='status-warning'>⚠️ StatefulSet $NAME 命名不规范，建议删除重建</div>" >> "$HTML_FILE"
            json_entries+=("{\"resource_type\":\"StatefulSet\",\"name\":\"$NAME\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
        fi
    done
fi

# ------------------------------
# 检测 Service
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<h3>Service</h3>
EOF
SERVICES_TO_CHECK=("$SERVICE_PRIMARY_STANDARD" "$SERVICE_REPLICA_STANDARD")
for svc in "${SERVICES_TO_CHECK[@]}"; do
    if echo "$SERVICE_LIST" | grep -q "/$svc"; then
        echo "<div class='status-ok'>✅ Service $svc 已存在且命名规范正确</div>" >> "$HTML_FILE"
    else
        echo "<div class='status-missing'>❌ Service $svc 不存在，需要创建</div>" >> "$HTML_FILE"
        json_entries+=("{\"resource_type\":\"Service\",\"name\":\"$svc\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
    fi
done

# ------------------------------
# 检测 PVC
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<h3>PVC</h3>
EOF
if [[ -z "$PVC_LIST" ]]; then
    echo "<div class='status-missing'>❌ PVC 未发现，需要创建</div>" >> "$HTML_FILE"
    json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"$PVC_PATTERN*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    for pvc in $PVC_LIST; do
        if [[ "$pvc" == ${PVC_PATTERN}* ]]; then
            echo "<div class='status-ok'>✅ PVC $pvc 命名规范正确</div>" >> "$HTML_FILE"
        else
            echo "<div class='status-warning'>⚠️ PVC $pvc 命名不规范，建议删除重建</div>" >> "$HTML_FILE"
            json_entries+=("{\"resource_type\":\"PVC\",\"name\":\"$pvc\",\"status\":\"命名不规范\",\"app\":\"$APP_NAME\"}")
        fi
    done
fi

# ------------------------------
# 检测 Pod
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<h3>Pod 状态</h3>
EOF
if [[ -z "$POD_STATUS" ]]; then
    echo "<div class='status-missing'>❌ Pod 未发现</div>" >> "$HTML_FILE"
    json_entries+=("{\"resource_type\":\"Pod\",\"name\":\"*\",\"status\":\"不存在\",\"app\":\"$APP_NAME\"}")
else
    while read -r line; do
        POD_NAME=$(echo $line | awk '{print $1}')
        STATUS=$(echo $line | awk '{print $2}')
        CASE_CLASS="status-missing"
        [[ "$STATUS" == "Running" ]] && CASE_CLASS="status-ok"
        [[ "$STATUS" == "Pending" ]] && CASE_CLASS="status-warning"
        echo "<div class='$CASE_CLASS'>$POD_NAME : $STATUS</div>" >> "$HTML_FILE"
    done <<< "$POD_STATUS"
fi

# ------------------------------
# HTML Footer
# ------------------------------
cat >> "$HTML_FILE" <<EOF
<div style="margin-top:20px;font-size:12px;color:#888;text-align:center">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>
</div></div>
</body>
</html>
EOF

# ------------------------------
# 输出 JSON 返回值
# ------------------------------
if [ ${#json_entries[@]} -eq 0 ]; then
    # 所有资源都存在且命名规范，返回空
    echo ""
else
    # 打印标准 JSON
    printf "[\n%s\n]\n" "$(IFS=,; echo "${json_entries[*]}")"
fi

# ------------------------------
# 保存 JSON 文件供参考
# ------------------------------
if [ ${#json_entries[@]} -ne 0 ]; then
    printf "[\n%s\n]\n" "$(IFS=,; echo "${json_entries[*]}")" > "$JSON_FILE"
fi

echo "✅ PostgreSQL HTML 报告生成完成: $HTML_FILE" >&2
