#!/bin/bash
# ============================================
# n8n 一键部署 + 稳定输出 v4.3.5
# 适用: 控制中心部署 Pod 到 containerd 边缘节点
# 执行位置: 控制中心
# 前提: agent01 已安装 containerd, /data/n8n 已创建, 镜像已拉好
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
NODEPORT=31678
STORAGE_PATH="/data/n8n"

clear
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n 一键部署 + 稳定输出 v4.3.5       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# --- 步骤1: 检查控制中心环境 ---
echo -e "${YELLOW}[1/5] 检查控制中心环境...${NC}"
if ! command -v kubectl &>/dev/null; then
    echo -e "${RED}✗ kubectl 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 已安装${NC}"

if ! kubectl get nodes &>/dev/null; then
    echo -e "${RED}✗ 无法连接到 Kubernetes 集群${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 集群连接正常${NC}"
echo ""

# --- 步骤2: 检查边缘节点状态 ---
echo -e "${YELLOW}[2/5] 检查边缘节点状态: ${EDGE_NODE}${NC}"
NODE_STATUS=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_STATUS" != "True" ]; then
    echo -e "${RED}✗ 节点 ${EDGE_NODE} 未 Ready${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 节点 Ready${NC}"

# --- 步骤2b: 检查 containerd 镜像 ---
echo -e "${YELLOW}[2b/5] 检查边缘节点 n8n 镜像...${NC}"
ssh ${EDGE_NODE} "sudo ctr -n k8s.io images list | grep n8n" &>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ agent01 未找到 n8n 镜像${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 镜像就绪${NC}"
echo ""

# --- 步骤3: 创建 n8n Service ---
echo -e "${YELLOW}[3/5] 创建 n8n Service...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: n8n-service
  namespace: default
spec:
  type: NodePort
  ports:
  - port: 5678
    targetPort: 5678
    nodePort: ${NODEPORT}
  selector:
    app: n8n
EOF
echo -e "${GREEN}✓ Service 已创建${NC}"
echo ""

# --- 步骤4: 创建 n8n Deployment ---
echo -e "${YELLOW}[4/5] 创建 n8n Deployment...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: default
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

# --- 步骤5: 等待 Pod 就绪 ---
echo -e "${YELLOW}[5/5] 等待 n8n Pod 就绪...${NC}"
COUNT=0
while true; do
    POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    POD_STATUS=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" == "Running" ]; then
        echo -e "${GREEN}✓ Pod 就绪: $POD_NAME${NC}"
        break
    fi
    COUNT=$((COUNT+1))
    echo -n "."
    sleep 5
    if [ $COUNT -ge 24 ]; then
        echo -e "\n${YELLOW}⚠ Pod 还未就绪，请检查 agent01 containerd 日志${NC}"
        break
    fi
done

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}              n8n 部署完成！${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""
echo -e "Pod 名称: ${GREEN}$POD_NAME${NC}"
echo -e "访问地址: ${GREEN}http://${NODE_IP}:${NODEPORT}${NC}"
echo -e "查看日志: ${YELLOW}kubectl logs -f $POD_NAME${NC}"
echo -e "查看 Pod:  ${YELLOW}kubectl get pods -l app=n8n -o wide${NC}"
echo ""
read -p "是否查看实时日志？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl logs -f $POD_NAME
fi

exit 0
