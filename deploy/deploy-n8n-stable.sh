#!/bin/bash
# ============================================
# n8n 一键部署脚本 (稳定版)
# 版本: 4.2.0
# 适用环境: KubeEdge + Containerd
# 执行位置: 直接在 agent01 节点上执行（Edge 节点）
# ============================================

set -e

# -------------------------------
# 配置区域（可根据实际修改）
NODE_IP="192.168.1.20"   # agent01 节点 IP
NODEPORT=31678
STORAGE_PATH="/data/n8n"
NAMESPACE="default"
# -------------------------------

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印标题
clear
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          n8n 一键部署脚本 v4.2.0         ║${NC}"
echo -e "${BLUE}║   直接在 agent01 节点执行，无需 SSH       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# -------------------------------
# 步骤1: 检查 kubectl 和节点状态
echo -e "${YELLOW}[1/5] 检查 kubectl 和节点状态...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 已安装${NC}"

NODE_READY=$(kubectl get node -o jsonpath='{.items[?(@.metadata.name=="agent01")].status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_READY" != "True" ]; then
    echo -e "${RED}✗ 节点 agent01 状态不是 Ready (当前: ${NODE_READY})${NC}"
    echo "请在 agent01 上检查 kubelet 和 edgecore 服务是否正常"
    exit 1
fi
echo -e "${GREEN}✓ 节点 Ready${NC}"
echo ""

# -------------------------------
# 步骤2: 创建数据目录
echo -e "${YELLOW}[2/5] 创建数据目录: ${STORAGE_PATH}${NC}"

sudo mkdir -p ${STORAGE_PATH}
sudo chmod 777 ${STORAGE_PATH}

echo -e "${GREEN}✓ 数据目录已准备好${NC}"
echo ""

# -------------------------------
# 步骤3: 创建 NodePort 服务
echo -e "${YELLOW}[3/5] 创建 n8n Service...${NC}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: n8n-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: n8n
  ports:
    - port: 5678
      targetPort: 5678
      nodePort: ${NODEPORT}
EOF

echo -e "${GREEN}✓ Service 已创建${NC}"
echo ""

# -------------------------------
# 步骤4: 创建 Deployment
echo -e "${YELLOW}[4/5] 部署 n8n Deployment...${NC}"

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      nodeSelector:
        kubernetes.io/hostname: agent01
      tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Exists"
        effect: "NoSchedule"
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        ports:
        - containerPort: 5678
        env:
        - name: N8N_PORT
          value: "5678"
        - name: N8N_HOST
          value: "${NODE_IP}"
        - name: WEBHOOK_URL
          value: "http://${NODE_IP}:${NODEPORT}"
        volumeMounts:
        - name: n8n-data
          mountPath: /home/node/.n8n
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 20
          periodSeconds: 5
      volumes:
      - name: n8n-data
        hostPath:
          path: ${STORAGE_PATH}
EOF

echo -e "${GREEN}✓ Deployment 已创建${NC}"
echo ""

# -------------------------------
# 步骤5: 等待 Pod Ready
echo -e "${YELLOW}[5/5] 等待 Pod 就绪...${NC}"

kubectl wait --for=condition=ready pod -l app=n8n --timeout=180s || \
echo -e "${RED}⚠ Pod 未能在 180 秒内就绪，可能节点资源不足或目录权限问题${NC}"

POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}')

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}n8n 部署完成！${NC}"
echo -e "${GREEN}Pod 名称: ${POD_NAME}${NC}"
echo -e "${GREEN}访问地址: http://${NODE_IP}:${NODEPORT}${NC}"
echo -e "${GREEN}查看日志: kubectl logs -f ${POD_NAME}${NC}"
echo -e "${GREEN}查看 Pod: kubectl get pods -l app=n8n -o wide${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
