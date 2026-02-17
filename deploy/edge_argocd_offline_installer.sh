#!/bin/bash
set -e

NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

# 集群信息
KUBECONFIG=${KUBECONFIG:-"$HOME/.kube/config"}
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "[INFO] 当前节点 IP: $NODE_IP"
echo "[INFO] 当前 KUBECONFIG: $KUBECONFIG"

# 检查命名空间
NS="argocd"
if kubectl get ns "$NS" &>/dev/null; then
    echo "[INFO] 命名空间 $NS 已存在"
else
    echo "[INFO] 创建命名空间 $NS"
    kubectl create ns "$NS"
fi

# 检查 StorageClass
SC="local-path"
if kubectl get sc "$SC" &>/dev/null; then
    echo "[INFO] StorageClass $SC 已存在"
else
    echo "[INFO] StorageClass $SC 不存在，自动部署 local-path-provisioner"
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    echo "[INFO] 等待 local-path-provisioner Pod 就绪..."
    kubectl -n local-path-storage wait --for=condition=Ready pod -l app=local-path-provisioner --timeout=120s
fi

# 拉取必要镜像
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)
for img in "${IMAGES[@]}"; do
    echo "[INFO] 拉取镜像 $img"
    sudo ctr -n k8s.io images pull "$img"
done

# 安装 Helm（如果没有）
if ! command -v helm &>/dev/null; then
    echo "[INFO] Helm 未安装，正在安装..."
    curl -fsSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz | tar -xz
    sudo mv linux-amd64/helm /usr/local/bin/helm
fi

# 添加 Argo Helm 仓库
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 随机选择 10000~11000 的 NodePort
NODEPORT=$((10000 + RANDOM % 1000))
echo "[INFO] 选择 NodePort: $NODEPORT"

# 部署 ArgoCD（NodePort）
echo "[INFO] 安装 ArgoCD Helm Chart (NodePort)..."
helm upgrade --install argocd argo/argo-cd \
    -n argocd \
    --set server.service.type=NodePort \
    --set server.service.nodePort="$NODEPORT" \
    --wait

# 获取初始密码
ADMIN_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 生成 HTML 文件
HTML_FILE="$NAS_DIR/argocd_login.html"
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>ArgoCD 登录信息</title>
</head>
<body>
<h2>ArgoCD 登录信息</h2>
<ul>
<li>URL: <a href="http://$NODE_IP:$NODEPORT" target="_blank">http://$NODE_IP:$NODEPORT</a></li>
<li>账号: <b>admin</b></li>
<li>密码: <b>$ADMIN_SECRET</b></li>
</ul>
<p>请妥善保存初始密码，首次登录后可修改。</p>
</body>
</html>
EOF

echo "[INFO] HTML 登录页面已生成: $HTML_FILE"
echo "[SUCCESS] ArgoCD 安装完成，可通过 NodePort 访问"
