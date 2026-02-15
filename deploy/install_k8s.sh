#!/bin/bash
set -e

# 1. 环境深度清理
echo "--- 正在清理旧残留 ---"
sudo kubeadm reset -f || true
sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet $HOME/.kube
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -X

# 2. 系统参数配置 (针对 K8s 优化)
echo "--- 配置内核参数 ---"
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

# 3. 安装 Containerd (配置 Cgroup 驱动)
echo "--- 安装运行时 ---"
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# 4. 安装 K8s v1.23.0 (使用新版阿里云源)
echo "--- 安装 K8s 组件 ---"
sudo apt-get install -y apt-transport-https curl
curl -fsSL https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet=1.23.0-00 kubeadm=1.23.0-00 kubectl=1.23.0-00
sudo apt-mark hold kubelet kubeadm kubectl

# 5. 初始化集群 (强制指定 API 地址防止 8080 错误)
echo "--- 初始化 Master ---"
sudo kubeadm init \
  --apiserver-advertise-address=192.168.1.10 \
  --image-repository registry.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.0 \
  --pod-network-cidr=10.244.0.0/16

# 6. 配置权限
mkdir -p $HOME/.kube
sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 7. 自动解除污点 (让单机或双节点能跑插件)
kubectl taint nodes --all node-role.kubernetes.io/master- || true
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# 8. 安装网络插件
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "--- Master 安装完成！请复制下方最后生成的 join 命令到 Worker 节点 ---"
