#!/bin/bash

# ================================
# ArgoCD NodePort 强制指定版本
# 使用方式:
# bash fix_argocd_port.sh 30099 30100
# ================================

HTTP_PORT=$1
HTTPS_PORT=$2

if [ -z "$HTTP_PORT" ] || [ -z "$HTTPS_PORT" ]; then
  echo "❌ 用法: bash fix_argocd_port.sh <http_port> <https_port>"
  exit 1
fi

if [ "$HTTP_PORT" -lt 30000 ] || [ "$HTTP_PORT" -gt 32767 ]; then
  echo "❌ HTTP 端口必须在 30000-32767 之间"
  exit 1
fi

if [ "$HTTPS_PORT" -lt 30000 ] || [ "$HTTPS_PORT" -gt 32767 ]; then
  echo "❌ HTTPS 端口必须在 30000-32767 之间"
  exit 1
fi

echo "🔹 检查 Kubernetes..."

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "❌ Kubernetes 未正常运行"
  exit 1
fi

echo "✅ Kubernetes 正常"

echo "🔹 修改 ArgoCD Service..."

kubectl -n argocd delete svc argocd-server --ignore-not-found=true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: argocd-server
  namespace: argocd
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: argocd-server
  ports:
    - name: http
      port: 80
      targetPort: 8080
      nodePort: ${HTTP_PORT}
      protocol: TCP
    - name: https
      port: 443
      targetPort: 8080
      nodePort: ${HTTPS_PORT}
      protocol: TCP
EOF

echo "✅ Service 修改完成"

sleep 3

echo "🔹 当前 Service 状态:"
kubectl -n argocd get svc argocd-server

# =========================
# 自动开放防火墙
# =========================

echo "🔹 检查防火墙..."

if command -v ufw >/dev/null 2>&1; then
  echo "🔹 Ubuntu 防火墙检测到"
  sudo ufw allow ${HTTP_PORT}/tcp
  sudo ufw allow ${HTTPS_PORT}/tcp
  echo "✅ ufw 已放行端口"
elif command -v firewall-cmd >/dev/null 2>&1; then
  echo "🔹 CentOS 防火墙检测到"
  sudo firewall-cmd --add-port=${HTTP_PORT}/tcp --permanent
  sudo firewall-cmd --add-port=${HTTPS_PORT}/tcp --permanent
  sudo firewall-cmd --reload
  echo "✅ firewalld 已放行端口"
else
  echo "⚠️ 未检测到防火墙或防火墙未开启"
fi

sleep 2

echo "🔹 检查端口监听..."
ss -lntp | grep ${HTTPS_PORT}

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo "======================================="
echo "🎉 完成！"
echo ""
echo "访问地址:"
echo "https://${SERVER_IP}:${HTTPS_PORT}"
echo ""
echo "如果浏览器提示证书不安全，选择继续访问即可。"
echo "======================================="
