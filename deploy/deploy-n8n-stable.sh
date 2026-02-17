#!/bin/bash
# ============================================
# n8n 一键部署脚本 v4.3.4 (稳定版)
# KubeEdge + containerd
# 执行位置: 控制中心
# 前提: 边缘节点已安装 edgecore 并可用
#       边缘节点已预拉镜像 (busybox + n8nio/n8n)
# ============================================

set -e

# ================= 配置 =====================
EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
NODEPORT=31678
STORAGE_PATH="/data/n8n"
NAMESPACE="default"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ================= 标题 =====================
clear
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n 一键部署 + 稳定输出 v4.3.4       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# ================= 步骤1: 控制中心检查 =====================
echo -e "${YELLOW}[1/6] 检查控制中心环境...${NC}"
command -v kubectl >/dev/null || { echo -e "${RED}✗ kubectl 未安装${NC}"; exit 1; }
echo -e "${GREEN}✓ kubectl 已安装${NC}"

kubectl get nodes >/dev/null || { echo -e "${RED}✗ 无法连接 Kubernetes 集群${NC}"; exit 1; }
echo -e "${GREEN}✓ 集群连接正常${NC}"
echo ""

# ================= 步骤2: 边缘节点检查 =====================
echo -e "${YELLOW}[2/6] 检查边缘节点状态: ${EDGE_NODE}${NC}"
NODE_READY=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_READY" != "True" ]; then
    echo -e "${RED}✗ 节点 ${EDGE_NODE} 未 Ready (当前: ${NODE_READY})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 节点 Ready${NC}"
echo ""

# ================= 步骤2b: 数据目录创建 =====================
echo -e "${YELLOW}[2b] 在边缘节点创建数据目录: ${STORAGE_PATH}${NC}"
kubectl run n8n-dir-prepare \
  --image=busybox \
  --restart=Never \
  --overrides="{
    \"spec\": {
      \"nodeName\": \"${EDGE_NODE}\",
      \"containers\": [{
        \"name\": \"prepare\",
        \"image\": \"busybox\",
        \"command\": [\"sh\", \"-c\", \"mkdir -p ${STORAGE_PATH} && chmod 777 ${STORAGE_PATH} && echo '目录创建完成'\"] 
      }]
    }
  }" >/dev/null

# 循环等待 Pod 完成 (带呼吸点)
echo "等待目录创建完成..."
for i in {1..12}; do
    STATUS=$(kubectl get pod n8n-dir-prepare -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    echo -n "."
    sleep 5
    if [ "$STATUS" == "Succeeded" ]; then
        break
    fi
done
echo ""

kubectl delete pod n8n-dir-prepare --force --grace-period=0 >/dev/null 2>&1
echo -e "${GREEN}✓ 数据目录已创建: ${STORAGE_PATH}${NC}"
echo ""

# ================= 步骤3: 创建 Service =====================
echo -e "${YELLOW}[3/6] 创建 n8n Service...${NC}"
cat <<SVC | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: n8n-service
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  ports:
  - port: 5678
    targetPort: 5678
    nodePort: ${NODEPORT}
  selector:
    app: n8n
SVC
echo -e "${GREEN}✓ Service 已创建${NC}"
echo ""

# ================= 步骤4: 创建 Deployment =====================
echo -e "${YELLOW}[4/6] 创建 n8n Deployment...${NC}"
cat <<DEPLOY | kubectl apply -f -
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
DEPLOY
echo -e "${GREEN}✓ Deployment 已创建${NC}"
echo ""

# ================= 步骤5: 等待 Pod 就绪 =====================
echo -e "${YELLOW}[5/6] 等待 n8n Pod 就绪...${NC}"

TIMEOUT=120
INTERVAL=5
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    POD_STATUS=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
    POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    echo -n "."
    if [ "$POD_STATUS" == "Running" ]; then
        echo -e "\n${GREEN}✓ Pod 已就绪: ${POD_NAME}${NC}"
        break
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ "$POD_STATUS" != "Running" ]; then
    echo -e "\n${YELLOW}⚠ Pod 当前状态: ${POD_STATUS}${NC}"
    echo "查看详情: kubectl describe pod -l app=n8n"
fi

# ================= 步骤6: 完整信息 =====================
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}               n8n 部署完成！${NC}"
echo -e "${GREEN}Pod 名称: ${POD_NAME}${NC}"
echo -e "${GREEN}访问地址: http://${NODE_IP}:${NODEPORT}${NC}"
echo -e "${GREEN}查看日志: kubectl logs -f ${POD_NAME}${NC}"
echo -e "${GREEN}查看 Pod: kubectl get pods -l app=n8n -o wide${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo ""

# ================= 可选: 查看实时日志 =====================
read -p "是否查看实时日志？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl logs -f -l app=n8n
fi

exit 0
