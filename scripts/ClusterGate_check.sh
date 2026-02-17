#!/bin/bash
# ====================================================================
# 🤖 ClusterGate - 企业级防火墙端口可视化配置
# 生成 HTML 报告 + 可操作复选框 + 生成防火墙脚本按钮
# ====================================================================

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_LOG_DIR="/mnt/truenas"

REPORT_FILE="${NAS_LOG_DIR}/ClusterGate_ports_${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/ClusterGate_ports_${TIMESTAMP}.log"

PORTS=(6443 10000 10002 8080 443)
CONTROL_IP=$(hostname -I | awk '{print $1}')

mkdir -p "$NAS_LOG_DIR"

log() { echo -e "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOG_FILE"; }

# ---------------- 端口检测 ----------------
log "🔹 检测本机端口..."
PORT_STATUS=()
for PORT in "${PORTS[@]}"; do
    if command -v nc >/dev/null 2>&1; then
        if nc -z -w 2 localhost $PORT &>/dev/null; then
            STATUS="可达"
            CHECKED=""
        else
            STATUS="不可达"
            CHECKED="checked"
        fi
    else
        STATUS="nc未安装"
        CHECKED=""
    fi
    PORT_STATUS+=("$PORT:$STATUS:$CHECKED")
    log "端口 $PORT: $STATUS"
done

# ---------------- 生成 HTML ----------------
PORT_HTML=""
for entry in "${PORT_STATUS[@]}"; do
    PORT=${entry%%:*}
    STATUS_TMP=${entry#*:}
    STATUS=${STATUS_TMP%%:*}
    CHECKED=${entry##*:}
    PORT_HTML+="<tr>
<td>$PORT</td>
<td>$STATUS</td>
<td><input type='checkbox' $CHECKED data-port='$PORT' title='选中表示端口不可达，需要开放'></td>
</tr>"
done

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>ClusterGate - 可视化防火墙端口控制</title>
<style>
body { font-family: sans-serif; margin: 30px; background: #f0f2f5; }
h1 { color: #1a73e8; }
table { border-collapse: collapse; width: 60%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background: #f8f9fa; }
button { margin-top: 10px; padding: 8px 12px; font-size: 14px; }
</style>
</head>
<body>
<h1>ClusterGate - 防火墙端口控制</h1>
<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 本机IP: $CONTROL_IP</p>
<table>
<tr><th>端口</th><th>状态</th><th>开放控制</th></tr>
$PORT_HTML
</table>
<button onclick="generateScript()">生成防火墙脚本</button>
<pre id="scriptOutput"></pre>

<script>
function generateScript() {
    const checkboxes = document.querySelectorAll('input[type="checkbox"]');
    let script = "#!/bin/bash\\n";
    script += "# 自动生成的 UFW 防火墙脚本\\n";
    checkboxes.forEach(cb => {
        if(cb.checked){
            const port = cb.getAttribute('data-port');
            script += "sudo ufw allow " + port + "/tcp\\n";
        }
    });
    document.getElementById('scriptOutput').textContent = script;
}
</script>
</body>
</html>
EOF

log "✅ HTML报告生成完成: $REPORT_FILE"
log "日志文件: $LOG_FILE"
