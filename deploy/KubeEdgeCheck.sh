#!/bin/bash
# ==============================================
# KubeEdge Edge 节点健康检查脚本
# 在 Edge 节点执行
# ==============================================

echo "=== 1. 系统信息 ==="
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I | awk '{print $1}')"
echo "Date: $(date)"
echo ""

echo "=== 2. Containerd 状态 ==="
sudo systemctl status containerd --no-pager
echo ""

echo "=== 3. EdgeCore 服务状态 ==="
sudo systemctl status edgecore --no-pager
echo ""

echo "=== 4. EdgeCore 日志最近 50 行 ==="
sudo journalctl -u edgecore -n 50 --no-pager
echo ""

echo "=== 5. /etc/kubeedge 目录情况 ==="
ls -l /etc/kubeedge
echo ""

echo "=== 6. KubeEdge 管理目录资源情况 ==="
echo "Configs:"
ls -l /etc/kubeedge/config
echo ""
echo "Certificates:"
ls -l /etc/kubeedge/certs
echo ""

echo "=== 7. Node 与 CloudCore 通信测试 ==="
CLOUD_IP="192.168.1.10"
echo "Ping CloudCore ($CLOUD_IP):"
ping -c 3 $CLOUD_IP
echo ""

echo "Check EdgeCore can reach CloudCore API port 10000:"
nc -zv $CLOUD_IP 10000
echo ""

echo "=== 8. Suggestion ==="
echo "1. 如果 containerd 或 edgecore 没启动，先 systemctl restart containerd/edgecore"
echo "2. 如果 /etc/kubeedge 缺少文件，可能需要重新 join"
echo "3. 如果 ping 或 nc 失败，检查网络和防火墙"
echo "=== Health Check Complete ==="
