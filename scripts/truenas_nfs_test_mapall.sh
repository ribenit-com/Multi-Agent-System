#!/bin/bash
set -e

# ======= 配置区 ======
TRUENAS_IP="192.168.1.6"
NFS_PATH="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
LOCAL_MOUNT="/mnt/truenas"

TIMESTAMP=$(date +%F_%H%M%S)
HOST_IP=$(hostname -I | awk '{print $1}')
LOCAL_LOG="/var/log/truenas_nfs_test_${TIMESTAMP}.log"

# 输出到控制台 + 日志文件
exec > >(tee -a "$LOCAL_LOG") 2>&1

echo "======================================"
echo " TrueNAS NFS Mount Test (mapall_user mode)"
echo " Time       : $(date)"
echo " Host IP    : $HOST_IP"
echo " TrueNAS IP : $TRUENAS_IP"
echo " NFS Path   : $NFS_PATH"
echo " Local Mount: $LOCAL_MOUNT"
echo " Log File   : $LOCAL_LOG"
echo "======================================"

# 创建挂载点
mkdir -p "$LOCAL_MOUNT"

# 1. 网络连通检查（警告失败，不退出）
echo "[1] Testing connectivity to TrueNAS..."
if ping -c 3 "$TRUENAS_IP" &>/dev/null; then
    echo "[OK] Network reachable"
else
    echo "[WARN] Cannot reach TrueNAS ($TRUENAS_IP), continuing..."
fi

# 2. 卸载旧挂载
if mountpoint -q "$LOCAL_MOUNT"; then
    echo "[2] Unmounting existing mount at $LOCAL_MOUNT..."
    sudo umount "$LOCAL_MOUNT" || true
fi

# 3. 挂载 TrueNAS NFS
echo "[3] Mounting NFS share..."
sudo mount -t nfs \
  -o vers=4.1,rsize=1048576,wsize=1048576,soft,timeo=600,retrans=3,_netdev \
  "$TRUENAS_IP:$NFS_PATH" "$LOCAL_MOUNT"

sleep 1

# 4. 挂载成功检测
if mountpoint -q "$LOCAL_MOUNT"; then
    echo "[OK] NFS mounted successfully at $LOCAL_MOUNT"
    ls -ld "$LOCAL_MOUNT"
else
    echo "[FAIL] NFS mount failed"
    exit 1
fi

# 5. 写入验证文件
VERIFY_FILE="$LOCAL_MOUNT/mount_verify_${HOST_IP}_${TIMESTAMP}.txt"
echo "[4] Writing NFS verification file..."
{
    echo "---- TrueNAS NFS Mount Verification ----"
    echo "Host      : $HOST_IP"
    echo "Time      : $(date)"
    echo "Status    : SUCCESS"
} > "$VERIFY_FILE"

echo "[✔] Written verify file: $VERIFY_FILE"

# 6. 生成 JSON 状态文件
JSON_FILE="$LOCAL_MOUNT/mount_status_${HOST_IP}_${TIMESTAMP}.json"
echo "[5] Writing JSON status file..."
cat > "$JSON_FILE" <<EOF
{
  "host_ip": "$HOST_IP",
  "truenas_ip": "$TRUENAS_IP",
  "nfs_path": "$NFS_PATH",
  "mount_point": "$LOCAL_MOUNT",
  "timestamp": "$(date)",
  "status": "SUCCESS"
}
EOF

echo "[✔] Written JSON status file: $JSON_FILE"

echo "======================================"
echo "[DONE] TrueNAS NFS Mount Test Completed"
echo " Local Log  : $LOCAL_LOG"
echo " NAS Verify : $VERIFY_FILE"
echo " NAS JSON   : $JSON_FILE"
echo "======================================"
