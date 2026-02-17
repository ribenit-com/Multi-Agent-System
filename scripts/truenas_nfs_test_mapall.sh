#!/bin/bash
set -e

# ======= 配置区 =======
TRUENAS_IP="192.168.1.6"
NFS_PATH="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
LOCAL_MOUNT="/mnt/truenas"

TIMESTAMP=$(date +%F_%H%M%S)
HOST_IP=$(hostname -I | awk '{print $1}')
LOCAL_LOG="/var/log/truenas_nfs_test_${TIMESTAMP}.log"

# 日志输出到控制台 + 文件
exec > >(tee -a "$LOCAL_LOG") 2>&1

echo "======================================"
echo " TrueNAS NFS Mount Test (auto detect NFS tools)"
echo " Time       : $(date)"
echo " Host IP    : $HOST_IP"
echo " TrueNAS IP : $TRUENAS_IP"
echo " NFS Path   : $NFS_PATH"
echo " Local Mount: $LOCAL_MOUNT"
echo " Log File   : $LOCAL_LOG"
echo "======================================"

# 1️⃣ 检查 NFS 工具是否安装
if ! command -v mount.nfs >/dev/null 2>&1; then
    echo "[ERROR] mount.nfs not found. Please install nfs-common:"
    echo "       sudo apt update && sudo apt install nfs-common -y"
    exit 1
fi
echo "[OK] NFS client tools found"

# 2️⃣ 检查网络连通
echo "[1] Testing connectivity to TrueNAS..."
if ping -c 3 "$TRUENAS_IP" &>/dev/null; then
    echo "[OK] Network reachable"
else
    echo "[WARN] Cannot reach TrueNAS ($TRUENAS_IP), continuing..."
fi

# 3️⃣ 创建挂载点
if [ ! -d "$LOCAL_MOUNT" ]; then
    echo "[2] Creating mount point $LOCAL_MOUNT..."
    sudo mkdir -p "$LOCAL_MOUNT"
fi

# 4️⃣ 卸载旧挂载
if mountpoint -q "$LOCAL_MOUNT"; then
    echo "[3] Unmounting existing mount at $LOCAL_MOUNT..."
    sudo umount "$LOCAL_MOUNT" || true
fi

# 5️⃣ 尝试挂载 NFS
MOUNT_SUCCESS=0
for VER in 4.1 4; do
    echo "[4] Trying to mount NFS version $VER..."
    if sudo mount -t nfs -o vers=$VER,rsize=1048576,wsize=1048576,soft,timeo=600,retrans=3,_netdev \
        "$TRUENAS_IP:$NFS_PATH" "$LOCAL_MOUNT"; then
        echo "[OK] Mounted NFS version $VER successfully"
        MOUNT_SUCCESS=1
        break
    else
        echo "[WARN] Failed to mount NFS version $VER, trying next..."
    fi
done

if [ $MOUNT_SUCCESS -ne 1 ]; then
    echo "[FAIL] NFS mount failed for all versions"
    exit 1
fi

# 6️⃣ 写入验证文件
VERIFY_FILE="$LOCAL_MOUNT/mount_verify_${HOST_IP}_${TIMESTAMP}.txt"
echo "[5] Writing verification file..."
{
    echo "---- TrueNAS NFS Mount Verification ----"
    echo "Host      : $HOST_IP"
    echo "Time      : $(date)"
    echo "Status    : SUCCESS"
} > "$VERIFY_FILE"
echo "[✔] Verification file: $VERIFY_FILE"

# 7️⃣ 生成 JSON 状态文件
JSON_FILE="$LOCAL_MOUNT/mount_status_${HOST_IP}_${TIMESTAMP}.json"
echo "[6] Writing JSON status file..."
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
echo "[✔] JSON status file: $JSON_FILE"

echo "======================================"
echo "[DONE] TrueNAS NFS Mount Test Completed"
echo " Log File   : $LOCAL_LOG"
echo " Verify File: $VERIFY_FILE"
echo " JSON File  : $JSON_FILE"
echo "======================================"
