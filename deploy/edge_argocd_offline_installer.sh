#!/bin/bash
set -e

NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

echo "[INFO] 🔹 当前节点 IP: $(hostname -I | awk '{print $1}')"
echo "[INFO] 🔹 当前 KUBECONFIG: ${KUBECONFIG:-$HOME/.kube/config}"

# 检查 kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl 未安装，请先安装 kubectl"
    exit 1
fi

# 检查 Helm
if ! command -v helm >/dev/null 2>&1; then
    echo "[INFO] Helm 未安装，正在安装 Helm..."
    curl -sSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz -o /tmp/helm.tar.gz
    tar -zxvf /tmp/helm.tar.gz -C /tmp
    sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
    echo "[INFO] Helm 安装完成: $(helm version --short)"
else
    echo "[INFO] Helm 已安装: $(helm version --short)"
fi

# 创建命名空间 argocd
if ! kubectl get ns argocd >/dev/null 2>&1; then
    echo "[INFO] 创建命名空间 argocd..."
    kubectl create ns argocd
else
    echo "[INFO] namespace argocd 已存在"
fi

# 检查 local-path StorageClass
if ! kubectl get sc local-path >/dev/null 2>&1; then
    echo "[INFO] StorageClass local-path 不存在，部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    # 等待 Pod 就绪
    kubectl -n local-path-storage wait --for=condition=Ready pod -l app=local-path-provisioner --timeout=120s
else
    echo "[INFO] StorageClass local-path 已存在"
fi

# 定义 ArgoCD 及依赖镜像
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)

echo "[INFO] 🔹 拉取镜像..."
for img in "${IMAGES[@]}"; do
    echo "  🔹 $img"
    sudo ctr -n k8s.io images pull "$img"
done
echo "[INFO] ✅ 所有镜像拉取完成"

# 添加 Argo Helm 仓库
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 安装 ArgoCD（NodePort 30100）
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set server.service.type=NodePort \
    --set server.service.nodePort=30100 \
    --wait

# 获取 ArgoCD 初始密码
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGO_USER="admin"
ARGO_IP=$(hostname -I | awk '{print $1}')
ARGO_PORT=30100

# 输出 HTML 文件到 NAS
HTML_FILE="$NAS_DIR/argocd_info.html"
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
<title>ArgoCD 登录信息</title>
<meta charset="utf-8">
</head>
<body>
<h2>ArgoCD 登录信息</h2>
<p><b>URL:</b> http://$ARGO_IP:$ARGO_PORT</p>
<p><b>账号:</b> $ARGO_USER</p>
<p><b>初始密码:</b> $ARGO_PASSWORD</p>
<p>⚠️ 请首次登录后修改密码</p>
</body>
</html>
EOF

chmod 644 "$HTML_FILE"

echo "[INFO] 🔹 ArgoCD 安装完成，登录信息已输出到 $HTML_FILE"
echo "     URL: http://$ARGO_IP:$ARGO_PORT"
echo "     账号: $ARGO_USER"
echo "     初始密码: $ARGO_PASSWORD"
