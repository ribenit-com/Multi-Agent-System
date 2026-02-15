#!/bin/bash
echo "开始深度清理 K3s 残留信息..."

# 1. 停止并移除 K3s 服务
# 使用 K3s 自带的卸载工具（Agent 节点通常是这个）
if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-agent-uninstall.sh
elif [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-uninstall.sh
fi

# 2. 强力杀掉所有残留的容器进程
# K3s 停止后，有时会有孤儿进程留在内存里
ps -ef | grep -E 'k3s|containerd|kube' | grep -v grep | awk '{print $2}' | xargs -r sudo kill -9

# 3. 清理物理网络设备 (预防 no route to host)
# 必须删掉 cni0 和 flannel.1，否则原生 K8s 无法创建新的网桥
echo "清理网络网桥..."
sudo ip link delete cni0 || true
sudo ip link delete flannel.1 || true
sudo ip link delete nodelocaldns || true

# 4. 抹除所有数据目录 (彻底清空握手和证书信息)
echo "抹除持久化数据..."
sudo rm -rf /var/lib/rancher/k3s
sudo rm -rf /etc/rancher/k3s
sudo rm -rf /run/k3s
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/kubernetes
sudo rm -rf /etc/cni/net.d/*

# 5. 清理 Iptables 规则 (K3s 的防火墙规则会干扰原生 K8s)
echo "重置防火墙规则..."
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X

echo "----------------------------------------------------"
echo "K3s 清理完成！该机器已回归 '白纸' 状态。"
echo "现在可以运行你的 '金牌加入脚本' 将其并入 1.10 集群了。"
echo "----------------------------------------------------"
