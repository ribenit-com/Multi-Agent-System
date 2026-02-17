#!/bin/bash
set -e

NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

echo "[INFO] 🔹 安装日志输出到 $NAS_DIR/edge_argocd_install_$(date +%Y%m%d_%H%M%S).log"

# 检查 kubectl
echo "[INFO] 🔹 检查 kubectl 可用性..."
kubectl version --client
kubectl cluster-info

# 检查/创建命名空间 argocd
echo "[INFO] 🔹 检查/创建命名空间 argocd..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd

# 检查本地镜像，如果不存在就拉取
IMAGES=(
  "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
  "docker.m.daocloud.io/library/redis:7.0.14-alpine"
  "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
  "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
  "m.daocloud.io/docker.io/library/alpine:latest"
)

echo "[INFO] 🔹 检查并拉取镜像..."
for img in "${IMAGES[@]}"; do
    if ! sudo ctr -n k8s.io images list | grep -q "${img##*/}"; then
        echo "[INFO] 拉取镜像 $img ..."
        sudo ctr -n k8s.io images pull "$img"
    else
        echo "[INFO] 镜像 $img 已存在"
    fi
done

# 检查 StorageClass local-path
echo "[INFO] 🔹 检查 StorageClass local-path..."
if ! kubectl get sc local-path >/dev/null 2>&1; then
    echo "[INFO] StorageClass local-path 不存在，部署 local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    # 等待 Pod 就绪
    kubectl wait --for=condition=Ready pod -l app=local-path-provisioner -n local-path-storage --timeout=120s
fi

# 安装 ArgoCD Helm Chart
echo "[INFO] 🔹 安装 ArgoCD Helm Chart..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set server.service.type=NodePort \
    --set server.service.nodePort=30100 \
    --wait

# 获取 admin 初始密码
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ADMIN_USER="admin"

# 生成 HTML 页面到 NAS
HTML_FILE="$NAS_DIR/argocd_login.html"
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>ArgoCD 登录信息</title>
</head>
<body>
  <h1>ArgoCD 登录信息</h1>
  <p>访问地址: <a href="http://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):30100" target="_blank">http://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'):30100</a></p>
  <p>用户名: $ADMIN_USER</p>
  <p>密码: $ADMIN_PASSWORD</p>
</body>
</html>
EOF

echo "[INFO] 🎉 ArgoCD 安装完成，HTML 登录页已生成: $HTML_FILE"
