# --- 1. 彻底关闭 Swap (K8s 刚需) ---
sudo swapoff -a
sudo sed -i '/swap/s/^/#/' /etc/fstab

# --- 2. 修复内核网络参数 ---
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

# --- 3. 极速安装容器运行时 (Docker/containerd) ---
# 既然之前的 K8s 找不到了，我们用最稳的 containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# --- 4. 正式重新初始化 ---
sudo kubeadm init \
  --image-repository registry.aliyuncs.com/google_containers \
  --kubernetes-version v1.23.0 \
  --pod-network-cidr=10.244.0.0/16 \
  --ignore-preflight-errors=all
