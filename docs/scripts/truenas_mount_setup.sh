#!/bin/bash

set -e

TRUENAS_IP="192.168.1.6"
NFS_PATH="/mnt/Agent-Ai/CSV_Data"
LOCAL_MOUNT="/mnt/truenas"

echo "======================================"
echo " TrueNAS Production Mount Setup"
echo "======================================"
echo "TrueNAS IP : $TRUENAS_IP"
echo "NFS Path   : $NFS_PATH"
echo "Local Path : $LOCAL_MOUNT"
echo "======================================"

# 1️⃣ 安装 nfs 工具
if ! command -v mount.nfs &>/dev/null; then
    echo "Installing NFS client..."
    if [ -f /etc/debian_version ]; then
        apt update && apt install -y nfs-common
    else
        yum install -y nfs-utils
    fi
fi

# 2️⃣ 创建目录
mkdir -p $LOCAL_MOUNT

# 3️⃣ 测试 NAS 连通性
echo "Testing connectivity to TrueNAS..."
if ! ping -c 3 $TRUENAS_IP &>/dev/null; then
    echo "ERROR: Cannot reach TrueNAS!"
    exit 1
fi

# 4️⃣ 测试 NFS 是否可见
echo "Checking NFS export..."
if ! showmount -e $TRUENAS_IP | grep -q "$NFS_PATH"; then
    echo "WARNING: NFS path not visible via showmount."
    echo "Continuing anyway (TrueNAS NFSv4 may not show exports)."
fi

# 5️⃣ 写入 fstab（防重复）
if ! grep -q "$TRUENAS_IP:$NFS_PATH" /etc/fstab; then
    echo "Adding entry to /etc/fstab..."

    echo "$TRUENAS_IP:$NFS_PATH  $LOCAL_MOUNT  nfs  vers=4.1,proto=tcp,soft,timeo=600,retrans=3,rsize=1048576,wsize=1048576,_netdev,x-systemd.automount,noatime  0  0" >> /etc/fstab
else
    echo "fstab entry already exists."
fi

# 6️⃣ 挂载
echo "Mounting..."
systemctl daemon-reload
mount -a

# 7️⃣ 验证
if mount | grep -q "$LOCAL_MOUNT"; then
    echo "Mount successful."

    echo "Testing write..."
    touch $LOCAL_MOUNT/mount_test_$(date +%s).txt

    echo "Write test successful."
else
    echo "ERROR: Mount failed!"
    exit 1
fi

echo "======================================"
echo " Production NFS Mount Completed"
echo "======================================"
