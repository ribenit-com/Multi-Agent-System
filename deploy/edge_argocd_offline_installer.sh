#!/bin/bash
set -e

NAS_DIR="/mnt/truenas"
LOG_FILE="$NAS_DIR/Enterprise_ArgoCD_Installer_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$NAS_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] 🔹 安装日志输出到 $LOG_FILE"

# ArgoCD NodePort
ARGOCD_NODEPORT=30100

echo "[INFO] 🔹 检查 kubectl 可用性..."
kubectl version --client
kubectl cluster-info

echo "[INFO] 🔹 检查/创建命名空间 argocd..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd

echo "[INFO] 🔹 安装 Helm..."
if ! command -v helm >/dev/null 2>&1; then
    curl -sSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz | tar -xz -C /tmp
    sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
fi
helm version

echo "[INFO] 🔹 添加 ArgoCD Helm 仓库..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "[INFO] 🔹 检查 StorageClass local-path..."
if ! kubectl get sc local-path >/dev/null 2>&1; then
    echo "[INFO] StorageClass local-path 不存在，部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    echo "[INFO] 🔹 等待 local-path-provisioner Pod 就绪..."
    kubectl wait --for=condition=Ready pod -l app=local-path-provisioner -n local-path-storage --timeout=120s
fi

# 预拉 ArgoCD 相关镜像
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)

echo "[INFO] 🔹 拉取 ArgoCD 相关镜像..."
for img in "${IMAGES[@]}"; do
    sudo ctr -n k8s.io images pull "$img"
done
echo "[INFO] ✅ 所有镜像拉取完成"

# 安装/升级 ArgoCD
echo "[INFO] 🔹 安装 ArgoCD Helm Chart..."
helm upgrade --install argocd argo/argo-cd \
    -n argocd \
    --set server.service.type=NodePort \
    --set server.service.nodePort=$ARGOCD_NODEPORT \
    --wait

# 开放防火墙端口
echo "[INFO] 🔹 开放防火墙端口 $ARGOCD_NODEPORT"
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow $ARGOCD_NODEPORT/tcp
    sudo ufw reload
fi
if command -v firewall-cmd >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-port=${ARGOCD_NODEPORT}/tcp
    sudo firewall-cmd --reload
fi

# 输出访问信息到 NAS
ARGOCD_SECRET=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
HTML_FILE="$NAS_DIR/argocd_access.html"
cat > "$HTML_FILE" <<EOF
<html>
<head><title>ArgoCD Access</title></head>
<body>
<h2>ArgoCD 登录信息</h2>
<p>URL: <a href="http://$(hostname -I | awk '{print $1}'):$ARGOCD_NODEPORT">http://$(hostname -I | awk '{print $1}'):$ARGOCD_NODEPORT</a></p>
<p>账号: admin</p>
<p>初始密码: $ARGOCD_SECRET</p>
</body>
</html>
EOF

echo "[INFO] 🔹 ArgoCD 安装完成，登录信息已生成: $HTML_FILE"
echo "URL: http://$(hostname -I | awk '{print $1}'):$ARGOCD_NODEPORT"
echo "账号: admin"
echo "初始密码: $ARGOCD_SECRET"
