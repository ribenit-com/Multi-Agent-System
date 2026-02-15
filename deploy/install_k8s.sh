#!/bin/bash
set -e

echo "--- 1. 深度清理残留 ---"
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet $HOME/.kube /etc/kubernetes
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -X

echo "--- 2. 系统环境优化 ---"
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "--- 3. 运行时配置 (强制 SystemdCgroup) ---"
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# 确保使用 SystemdCgroup，否则 kubelet 会启动失败
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- 4. 安装 K8s v1.23.0 组件 ---"
sudo apt-get install -y apt-transport-https curl
curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.23.0-00 kubeadm=1.23.0-00 kubectl=1.23.0-00
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- 5. 镜像库专项优化 (核心修复点) ---"
# 在 init 之前，手动强制拉取所有需要的镜像
# 这样可以避免 init 过程中因为拉取镜像过慢导致的超时卡死
sudo kubeadm config images pull \
  --image-repository registry.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.0

echo "--- 6. 初始化集群 ---"
# 指定 advertise-address 防止 kubectl 默认去找 localhost:8080
sudo kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --image-repository registry.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.0 \
  --pod-network-cidr=10.244.0.0/16 \
  --ignore-preflight-errors=all

echo "--- 安装完成！ ---"
