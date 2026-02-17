#!/bin/bash
set -e

# -----------------------------
# 配置
# -----------------------------
NAS_DIR="/mnt/truenas"
mkdir -p "$NAS_DIR"

ARGOCD_NAMESPACE="argocd"
STORAGECLASS_NAME="local-path"

# 离线镜像列表
IMAGES=(
  "m.daocloud.io/quay.io/argoproj/argocd:v2.9.1"
  "docker.m.daocloud.io/library/redis:7.0.14-alpine"
  "ghcr.m.daocloud.io/dexidp/dex:v2.37.0"
  "m.daocloud.io/docker.io/jimmidyson/configmap-reload:v0.8.0"
  "m.daocloud.io/docker.io/library/alpine:latest"
)

# -----------------------------
# 检查 kubectl
# -----------------------------
echo "🔹 当前节点 IP: $(hostname -I | awk '{print $1}')"
echo "🔹 当前 KUBECONFIG: ${KUBECONFIG:-$HOME/.kube/config}"

echo "🔹 检查 kubectl 可用性..."
kubectl version --client
kubectl get nodes

# -----------------------------
# 创建命名空间
# -----------------------------
echo "🔹 检查/创建命名空间 $ARGOCD_NAMESPACE..."
kubectl get ns "$ARGOCD_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$ARGOCD_NAMESPACE"
echo "ℹ️ namespace $ARGOCD_NAMESPACE 已存在或创建完成"

# -----------------------------
# 安装 Helm
# -----------------------------
if ! command -v helm &>/dev/null; then
  echo "⚠️ Helm 未安装，正在安装..."
  curl -sSL https://get.helm.sh/helm-v3.20.0-linux-amd64.tar.gz | tar xz -C /tmp
  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
fi

echo "🔹 Helm 版本信息："
helm version

echo "🔹 添加 Argo Helm 仓库..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# -----------------------------
# 检查 StorageClass
# -----------------------------
echo "🔹 检查 StorageClass $STORAGECLASS_NAME..."
if ! kubectl get sc "$STORAGECLASS_NAME" >/dev/null 2>&1; then
  echo "⚠️ StorageClass $STORAGECLASS_NAME 不存在，正在创建 local-path-provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  echo "🔹 等待 local-path-provisioner Pod 就绪..."
  kubectl -n local-path-storage wait --for=condition=Ready pod -l app=local-path-provisioner --timeout=120s
  echo "✅ StorageClass $STORAGECLASS_NAME 已创建并可用"
else
  echo "✅ StorageClass $STORAGECLASS_NAME 已存在"
fi

# -----------------------------
# 拉取镜像
# -----------------------------
echo "🔹 检查/拉取 ArgoCD 相关镜像..."
for img in "${IMAGES[@]}"; do
  echo "📥 拉取镜像: $img"
  if sudo ctr -n k8s.io images pull "$img"; then
    echo "✅ 成功: $img"
  else
    echo "❌ 镜像拉取失败: $img，请检查网络"
    exit 1
  fi
done
echo "✅ 所有镜像拉取完成"

# -----------------------------
# 安装 ArgoCD Helm Chart
# -----------------------------
echo "🔹 安装 ArgoCD Helm Chart..."
if helm -n "$ARGOCD_NAMESPACE" status argocd >/dev/null 2>&1; then
  helm -n "$ARGOCD_NAMESPACE" upgrade argocd argo/argo-cd
else
  helm -n "$ARGOCD_NAMESPACE" install argocd argo/argo-cd
fi

# -----------------------------
# 修改 ArgoCD Server 为 NodePort
# -----------------------------
echo "🔹 设置 ArgoCD Server 服务类型为 NodePort..."
kubectl -n "$ARGOCD_NAMESPACE" patch svc argocd-server -p '{"spec": {"type": "NodePort"}}'
NODEPORT=$(kubectl -n "$ARGOCD_NAMESPACE" get svc argocd-server -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')

# -----------------------------
# 生成 HTML 登录页
# -----------------------------
ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
cat <<EOF > "$NAS_DIR/argocd_login.html"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>ArgoCD 登录信息</title>
</head>
<body>
    <h1>ArgoCD 登录信息</h1>
    <p>URL: <a href="http://$(hostname -I | awk '{print $1}'):$NODEPORT" target="_blank">http://$(hostname -I | awk '{print $1}'):$NODEPORT</a></p>
    <p>账号: admin</p>
    <p>密码: $ARGOCD_PASSWORD</p>
</body>
</html>
EOF
echo "✅ ArgoCD 登录页已生成: $NAS_DIR/argocd_login.html"

echo "🎉 ArgoCD 安装完成，访问地址：http://$(hostname -I | awk '{print $1}'):$NODEPORT"
echo "    账号：admin"
echo "    密码：$ARGOCD_PASSWORD"
