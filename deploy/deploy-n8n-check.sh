#!/bin/bash
# ============================================
# n8n 一键部署脚本（稳定版，含环境检查）
# 版本: 4.3.0
# 执行位置: 控制中心 (cmaster01)
# 依赖: 控制中心已连接 KubeEdge 节点 agent01
# ============================================

set -e

# -------------------------------
# 配置区域
EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
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

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       n8n 一键部署 + 环境检查 v4.3.0      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# -------------------------------
# 步骤1: 检查控制中心环境
echo -e "${YELLOW}[1/5] 检查控制中心环境...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 已安装${NC}"

if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}✗ 无法连接到 Kubernetes 集群${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 集群连接正常${NC}"
echo ""

# -------------------------------
# 步骤2: 检查边缘节点环境
echo -e "${YELLOW}[2/5] 检查边缘节点环境: ${EDGE_NODE}${NC}"

NODE_READY=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_READY" != "True" ]; then
    echo -e "${RED}✗ 节点 ${EDGE_NODE} 状态不是 Ready (当前: ${NODE_READY})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 节点 Ready${NC}"

# 检查数据目录是否存在
kubectl run n8n-dir-check --rm -i --restart=Never \
  --image=busybox --overrides="{
  \"spec\": {
    \"nodeName\": \"${EDGE_NODE}\",
    \"containers\":[{
      \"name\":\"check\",
      \"image\":\"busybox\",
      \"command\":[\"sh\",\"-c\",\"if [ ! -d '${STORAGE_PATH}' ]; then mkdir -p '${STORAGE_PATH}' && chmod 777 '${STORAGE_PATH}'; fi; echo OK\"] 
    }]
  }
}" >/dev/null 2>&1
echo -e "${GREEN}✓ 数据目录检查/创建完成: ${STORAGE_PATH}${NC}"
echo ""

# -------------------------------
# 步骤3: 创建 Service
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
        kubernetes.io/hostname: ${EDGE_NODE}
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
echo -e "${RED}⚠ Pod 未能在 180 秒内就绪${NC}"

POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}')

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}n8n 部署完成！${NC}"
echo -e "${GREEN}Pod 名称: ${POD_NAME}${NC}"
echo -e "${GREEN}访问地址: http://${NODE_IP}:${NODEPORT}${NC}"
echo -e "${GREEN}查看日志: kubectl logs -f ${POD_NAME}${NC}"
echo -e "${GREEN}查看 Pod: kubectl get pods -l app=n8n -o wide${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
