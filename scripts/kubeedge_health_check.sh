#!/bin/bash
# ============================================
# KubeEdge 集群全面健康检测脚本（NAS版）
# 版本: 2.1.0
# 执行位置: 控制中心
# 输出: HTML健康报告 + 日志，保存到NAS
# ============================================

set -euo pipefail

# ================= 配置 =================
CONTROL_IP="192.168.1.10"
NETWORK_PREFIX="192.168.1"

# NAS路径配置
TRUENAS_IP="192.168.1.6"
NFS_PATH="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
LOCAL_MOUNT="/mnt/truenas"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
HOST_IP=$(hostname -I | awk '{print $1}')
LOCAL_LOG="$LOCAL_MOUNT/kubeedge-health-check-${TIMESTAMP}.log"
REPORT_FILE="$LOCAL_MOUNT/kubeedge-health-report-${TIMESTAMP}.html"

# ================= 自动更新脚本 =================
SCRIPT_URL="https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/scripts/kubeedge_health_check.sh"
SCRIPT_PATH="$HOME/kubeedge_health_check.sh"

echo "Checking for latest script version..."
wget -q -O "$SCRIPT_PATH.tmp" "$SCRIPT_URL"
if [ -f "$SCRIPT_PATH" ]; then
    DIFF=$(diff "$SCRIPT_PATH" "$SCRIPT_PATH.tmp" || true)
    if [ -n "$DIFF" ]; then
        echo "[INFO] Updating script to latest version..."
        mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    else
        echo "[OK] Script is already up-to-date"
        rm -f "$SCRIPT_PATH.tmp"
    fi
else
    echo "[INFO] Installing script for the first time..."
    mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
fi

# ================= 日志输出 =================
exec > >(tee -a "$LOCAL_LOG") 2>&1

# ================= 挂载 NAS =================
if ! command -v mount.nfs >/dev/null 2>&1; then
    echo "[INFO] nfs-common not found. Installing..."
    sudo apt update && sudo apt install -y nfs-common
fi

if [ ! -d "$LOCAL_MOUNT" ]; then
    echo "[INFO] Creating mount point $LOCAL_MOUNT..."
    sudo mkdir -p "$LOCAL_MOUNT"
fi

if mountpoint -q "$LOCAL_MOUNT"; then
    echo "[INFO] Unmounting existing mount..."
    sudo umount "$LOCAL_MOUNT" || true
fi

MOUNT_SUCCESS=0
for VER in 4.1 4 3; do
    echo "[INFO] Trying to mount NFS version $VER..."
    if sudo mount -v -t nfs -o vers=$VER,soft,timeo=10,retrans=2,rsize=1048576,wsize=1048576,_netdev \
        "$TRUENAS_IP:$NFS_PATH" "$LOCAL_MOUNT"; then
        echo "[OK] Mounted NFS version $VER successfully"
        MOUNT_SUCCESS=1
        break
    else
        echo "[WARN] Failed to mount NFS version $VER"
    fi
done

if [ $MOUNT_SUCCESS -ne 1 ]; then
    echo "[FAIL] All NFS mount attempts failed, exiting..."
    exit 1
fi

# ================= 删除旧文件 =================
[ -f "$REPORT_FILE" ] && rm -f "$REPORT_FILE"
[ -f "$LOCAL_LOG" ] && rm -f "$LOCAL_LOG"

# ================= 控制台颜色 =================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

TOTAL_CHECKS=0; PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""; ERROR_DETAILS=""

log() { echo -e "$1" | tee -a "$LOCAL_LOG"; }

# ================= 运行原健康检查 =================
# 这里直接把原健康检查逻辑放入
# 注意修改原有NAS路径保存日志和报告为 $LOCAL_MOUNT 下
# （你的原脚本从 # 开始的内容直接复制过来即可）

# 例如：
log "${BLUE}════════════════ KubeEdge 健康检测开始 (${TIMESTAMP}) ════════════════${NC}"

# ===== 1. 网络检查 =====
# ... 原有检查逻辑不变，只是 log 输出会写入 $LOCAL_LOG
# ... HTML 也写入 SECTION_HTML
# ===== 2. 硬件检查 =====
# ... CPU、内存、磁盘
# ===== 3. 配置检查 =====
# ... kubeconfig、KUBECONFIG、时区
# ===== 4. Kubernetes 服务 =====
# ... kubectl 连接、节点状态
# ===== 5. 边缘节点握手 =====
# ... 节点 Ready 状态、ping 测试

# ================= 生成 HTML 报告 =================
TOTAL_CHECKS=$((PASSED + WARN + FAILED))
HEALTH_SCORE=$((PASSED*100/TOTAL_CHECKS))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>KubeEdge 集群健康报告</title></head>
<body>
<h1>KubeEdge 集群健康检测报告</h1>
<p>生成时间: $(date) | 控制中心: $CONTROL_IP</p>
<p>总检查: $TOTAL_CHECKS, 通过: $PASSED, 警告: $WARN, 失败: $FAILED, 健康评分: $HEALTH_SCORE%</p>
<table border="1" cellpadding="5">
<tr><th>状态</th><th>检查项</th><th>结果</th><th>备注</th></tr>
$SECTION_HTML
</table>
EOF

if [ -n "$ERROR_DETAILS" ]; then
cat >> "$REPORT_FILE" <<EOF
<div style="color:red;">
<h2>错误详情</h2>
<p>$ERROR_DETAILS</p>
</div>
EOF
fi

cat >> "$REPORT_FILE" <<EOF
</body></html>
EOF

log "${GREEN}✅ 报告生成: $REPORT_FILE${NC}"
log "${GREEN}✅ 日志文件: $LOCAL_LOG${NC}"

# 自动打开报告
if [ -n "${DISPLAY:-}" ] && command -v xdg-open &>/dev/null; then
    xdg-open "$REPORT_FILE"
else
    log "提示: 使用浏览器打开报告: file://$REPORT_FILE"
fi

# ================= 返回状态码 =================
if [ $FAILED -gt 0 ]; then exit 1; else exit 0; fi
