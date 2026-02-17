#!/bin/bash
set -e

# ====== 配置 ======
TRUENAS_IP="192.168.1.6"
NFS_PATH="/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log"
LOCAL_MOUNT="/mnt/truenas"
LINUX_USER="zuandilong"  # 改成你本地用户
UID_GID=$(id -u $LINUX_USER):$(id -g $LINUX_USER)

TIMESTAMP=$(date +%F_%H%M%S)
HOST_IP=$(hostname -I | awk '{print $1}')
LOCAL_LOG="/var/log/truenas_nfs_test_${TIMESTAMP}.log"

# 所有输出写入日志
exec > >(tee -a $LOCAL_LOG) 2>&1

echo "======================================"
echo " TrueNAS NFS Mount Test"
echo "Time       : $(date)"
echo "Host IP    : $HOST_IP"
echo "TrueNAS IP : $TRUENAS_IP"
echo "NFS Path   : $NFS_PATH"
echo "Local Path : $LOCAL_MOUNT"
echo "Test User  : $LINUX_USER"
echo "Log File   : $LOCAL_LOG"
echo "======================================"

# 创建挂载目录
mkdir -p $LOCAL_MOUNT

# 测试网络
echo "Testing connectivity to TrueNAS..."
ping -c 3 $TRUENAS_IP

# 挂载
echo "Mounting NFS..."
sudo mount -t nfs -o vers=4.1,proto=tcp,soft,timeo=600,retrans=3,rsize=1048576,wsize=1048576,_netdev,uid=$(id -u $LINUX_USER),gid=$(id -g $LINUX_USER) $TRUENAS_IP:$NFS_PATH $LOCAL_MOUNT

sleep 2

# 验证挂载
if mount | grep -q "$LOCAL_MOUNT"; then
    echo "[OK] NFS mounted successfully"
else
    echo "[FAIL] NFS mount failed"
    exit 1
fi

# 写入 NAS 验证文件
VERIFY_FILE="$LOCAL_MOUNT/mount_verify_${HOST_IP}_${TIMESTAMP}.txt"
echo "Writing verification file to NAS..."
echo "TrueNAS NFS Mount Verification" > $VERIFY_FILE
echo "Host: $HOST_IP" >> $VERIFY_FILE
echo "Time: $(date)" >> $VERIFY_FILE
echo "Status: SUCCESS" >> $VERIFY_FILE

# 生成 JSON 状态文件
JSON_FILE="$LOCAL_MOUNT/mount_status_${HOST_IP}_${TIMESTAMP}.json"
cat <<EOF > $JSON_FILE
{
  "host_ip": "$HOST_IP",
  "truenas_ip": "$TRUENAS_IP",
  "nfs_path": "$NFS_PATH",
  "mount_point": "$LOCAL_MOUNT",
  "timestamp": "$(date)",
  "status": "SUCCESS"
}
EOF

echo "======================================"
echo "[DONE] NFS Mount Test Completed"
echo "Local Log  : $LOCAL_LOG"
echo "NAS Verify : $VERIFY_FILE"
echo "NAS JSON   : $JSON_FILE"
echo "======================================"
