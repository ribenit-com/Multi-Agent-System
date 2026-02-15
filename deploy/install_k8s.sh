#!/bin/bash
set -e

echo "----------------------------------------------------"
echo "开始构建原生 K8s 稳定版母盘 (v1.28)..."
echo "----------------------------------------------------"

# 1. 基础环境加固
echo "[1/7] 永久关闭 Swap 并优化内核参数..."
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 2. 安装并配置 Containerd
echo "[2/7] 安装并配置容器运行时 (CRI)..."
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# 核心：解决驱动冲突，这是 init 成功的关键
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# 3. 安装 K8s 三剑客
echo "[3/7] 下载 K8s v1.28 核心组件..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 4. 初始化集群
echo "[4/7] 正在初始化集群 (Pod 网段: 10.244.0.0/16)..."
# 必须指定 pod-network-cidr 以适配 Flannel
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# 5. 焊死权限钥匙 (解决 Permission Denied)
echo "[5/7] 配置持久化管理权限..."
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
grep -q "KUBECONFIG" ~/.bashrc || echo "export KUBECONFIG=\$HOME/.kube/config" >> ~/.bashrc

# 6. 注入网络灵魂 (Flannel)
echo "[6/7] 部署 Flannel 网络插件..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 7. 导出前自检
echo "[7/7] 等待节点就绪..."
sleep 10
kubectl get nodes
echo "----------------------------------------------------"
echo "安装完成！请确认状态为 Ready 后，即可导出母盘。"
echo "----------------------------------------------------"
