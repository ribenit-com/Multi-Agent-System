#!/bin/bash
# edge_argocd_offline_installer.sh
# 离线/在线安装 ArgoCD，并固定 NodePort 30100，生成 HTML 登录页到 NAS

set -e

# NAS 目录
NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

# NodePort 固定端口
NODEPORT=30100

# 检查 kubectl
echo "[INFO] 🔹 检查 kubectl 可用性..."
kubectl version --client

# 检查节点
echo "[INFO] 🔹 节点信息："
kubectl get nodes -o wide

# 创建 argocd 命名空间
echo "[INFO] 🔹 检查/创建命名空间 argocd..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd

# 安装 Helm（如果没有）
if ! command -v helm &>/dev/null; then
    echo "[INFO] 🔹 安装 Helm..."
    curl -sSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz -o /tmp/helm.tar.gz
    tar -xzf /tmp/helm.tar.gz -C /tmp
    sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
fi
helm version

# 检查 StorageClass local-path
echo "[INFO] 🔹 检查 StorageClass local-path..."
if ! kubectl get sc local-path >/dev/null 2>&1; then
    echo "[INFO] StorageClass local-path 不存在，部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    # 等待 Pod 就绪
    echo "[INFO] 等待 local-path-provisioner Pod 就绪..."
    kubectl wait --for=condition=ready pod -l app=local-path-provisioner -n local-path-storage --timeout=120s
fi

# 拉取离线镜像（可根据你的需要添加更多）
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)
echo "[INFO] 🔹 拉取必要镜像..."
for img in "${IMAGES[@]}"; do
    echo "[INFO] 🔹 拉取镜像 $img"
    sudo ctr -n k8s.io images pull "$img"
done
echo "[INFO] ✅ 所有镜像拉取完成"

# 添加 Argo Helm 仓库
echo "[INFO] 🔹 添加 Argo 仓库..."
helm repo add argo https://argoproj.github.io/argo-helm || true
helm repo update

# 创建自定义 values.yaml，用 NodePort 30100
TMP_VALUES=$(mktemp)
cat <<EOF >"$TMP_VALUES"
server:
  service:
    type: NodePort
    nodePort: $NODEPORT
    port: 443
    targetPort: 8080
EOF

# 安装/升级 ArgoCD
echo "[INFO] 🔹 安装 ArgoCD Helm Chart..."
helm upgrade --install argocd argo/argo-cd -n argocd -f "$TMP_VALUES"

# 等待 ArgoCD Pod 就绪
echo "[INFO] 🔹 等待 ArgoCD Pod 就绪..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

# 开放防火墙端口（仅针对 Ubuntu ufw 示例）
if command -v ufw &>/dev/null; then
    echo "[INFO] 🔹 开放防火墙端口 $NODEPORT..."
    sudo ufw allow "$NODEPORT"
fi

# 获取 admin 初始密码
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# 输出 HTML 页面到 NAS
HTML_FILE="$NAS_DIR/argocd_login.html"
cat <<EOF >"$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>ArgoCD 登录信息</title>
</head>
<body>
<h2>ArgoCD 登录信息</h2>
<p>URL: <a href="https://$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.name=="cmaster01")].status.addresses[?(@.type=="InternalIP")].address}'):$NODEPORT" target="_blank">访问 ArgoCD</a></p>
<p>账号: admin</p>
<p>初始密码: $ADMIN_PASSWORD</p>
</body>
</html>
EOF

echo "[INFO] 🎉 ArgoCD 安装完成，登录信息已生成：$HTML_FILE"
echo "[INFO] URL: https://$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.name=="cmaster01")].status.addresses[?(@.type=="InternalIP")].address}'):$NODEPORT"
echo "[INFO] 账号: admin"
echo "[INFO] 初始密码: $ADMIN_PASSWORD"
