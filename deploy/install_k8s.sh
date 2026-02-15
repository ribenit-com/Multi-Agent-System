#!/bin/bash
set -e # 遇错即停

echo "--- 1. 彻底清理旧环境与网络残留 ---"
sudo kubeadm reset -f || true
sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube* -y || true
sudo apt-get autoremove -y
sudo rm -rf ~/.kube /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni/net.d
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true

echo "--- 2. 系统基础环境配置 (Swap & Kernel) ---"
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

# 加载内核模块
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# 配置内核转发参数
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "--- 3. 安装并配置 Containerd 运行时 ---"
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# 关键修复：设置 SystemdCgroup 为 true，确保 K8s 运行稳定
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

echo "--- 4. 安装 K8s v1.23.0 官方组件 (阿里云源) ---"
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.23.0-00 kubeadm=1.23.0-00 kubectl=1.23.0-00
sudo apt-mark hold kubelet kubeadm kubectl

echo "--- 5. 使用阿里云镜像初始化集群 ---"
# 注意：pod-network-cidr 必须与后续 Flannel 配置一致
sudo kubeadm init \
  --image-repository registry.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.0 \
  --pod-network-cidr=10.244.0.0/16 \
  --ignore-preflight-errors=all

echo "--- 6. 配置普通用户管理权限 ---"
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "--- 7. 安装网络插件 (Flannel) ---"
# 只有安装了网络插件，Node 状态才会变为 Ready
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "--- 安装完成！请运行 'kubectl get nodes' 查看状态 ---"
