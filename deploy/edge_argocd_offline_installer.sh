#!/bin/bash
set -e

NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

echo "[INFO] 开始 ArgoCD 离线安装..."

# 固定 NodePort 端口
NODEPORT=10080
ARGOCD_NAMESPACE="argocd"

# 1. 创建命名空间
kubectl get ns $ARGOCD_NAMESPACE >/dev/null 2>&1 || kubectl create ns $ARGOCD_NAMESPACE
echo "[INFO] namespace $ARGOCD_NAMESPACE 已存在或创建完成"

# 2. 检查 StorageClass
STORAGECLASS=$(kubectl get sc local-path -o name 2>/dev/null || true)
if [ -z "$STORAGECLASS" ]; then
    echo "[INFO] local-path StorageClass 不存在，创建..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    echo "[INFO] 等待 local-path-provisioner Pod 就绪..."
    kubectl wait --for=condition=Ready pod -n local-path-storage -l app=local-path-provisioner --timeout=120s
fi
echo "[INFO] StorageClass local-path 已就绪"

# 3. 拉取离线镜像（ctr）
IMAGES=(
    "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
    "docker.m.daocloud.io/library/redis:7.0.14-alpine"
    "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
    "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
    "m.daocloud.io/docker.io/library/alpine:latest"
)

for img in "${IMAGES[@]}"; do
    echo "[INFO] 检查并拉取镜像 $img ..."
    sudo ctr -n k8s.io images pull "$img"
done

echo "[INFO] 所有镜像拉取完成"

# 4. 安装 ArgoCD 并修改 service 为 NodePort
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: $ARGOCD_NAMESPACE
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
    - port: 443
      targetPort: 8080
      nodePort: $NODEPORT
EOF

# 5. 使用 Helm 安装 ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd -n $ARGOCD_NAMESPACE \
    --set server.service.type=NodePort \
    --set server.service.nodePort=$NODEPORT

echo "[INFO] 等待 ArgoCD Pod 就绪..."
kubectl wait --for=condition=Ready pod -n $ARGOCD_NAMESPACE -l app.kubernetes.io/name=argocd-server --timeout=180s

# 6. 获取初始密码
ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
ARGOCD_USER="admin"

# 7. 生成 HTML 页面到 NAS
HTML_FILE="$NAS_DIR/argocd_login.html"
cat <<HTML > "$HTML_FILE"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>ArgoCD 登录信息</title>
</head>
<body>
<h2>ArgoCD 登录信息</h2>
<p>访问地址: <a href="https://$(hostname -I | awk '{print $1}'):$NODEPORT" target="_blank">https://$(hostname -I | awk '{print $1}'):$NODEPORT</a></p>
<p>用户名: $ARGOCD_USER</p>
<p>密码: $ARGOCD_PASSWORD</p>
</body>
</html>
HTML

# 8. 开放防火墙端口（CentOS/Ubuntu）
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "[INFO] 开放防火墙端口 $NODEPORT (firewalld)"
    sudo firewall-cmd --add-port=${NODEPORT}/tcp --permanent
    sudo firewall-cmd --reload
elif command -v ufw >/dev/null 2>&1; then
    echo "[INFO] 开放防火墙端口 $NODEPORT (ufw)"
    sudo ufw allow $NODEPORT/tcp
else
    echo "[WARN] 未检测到已知防火墙工具，请确保端口 $NODEPORT 可访问"
fi

echo "[INFO] ArgoCD 安装完成"
echo "[INFO] NodePort: $NODEPORT，HTML 登录页已生成: $HTML_FILE"
echo "[INFO] 使用浏览器访问: https://$(hostname -I | awk '{print $1}'):$NODEPORT"
