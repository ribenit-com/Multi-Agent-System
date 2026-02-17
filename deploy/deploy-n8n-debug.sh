#!/bin/bash
# ============================================
# n8n 一键部署 + Debug 输出 v4.3.3
# 带呼吸感反馈和镜像预拉取
# 执行位置: 控制中心 (cmaster01)
# 依赖: 已连接 KubeEdge 节点 agent01
# ============================================

set -e

EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
NODEPORT=31678
STORAGE_PATH="/data/n8n"
NAMESPACE="default"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   n8n 一键部署 + Debug 输出 v4.3.3       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# -------------------------------
# 1. 控制中心环境检查
echo -e "${YELLOW}[1/6] 检查控制中心环境...${NC}"
command -v kubectl >/dev/null || { echo -e "${RED}✗ kubectl 未安装${NC}"; exit 1; }
echo -e "${GREEN}✓ kubectl 已安装${NC}"

kubectl get nodes >/dev/null || { echo -e "${RED}✗ 无法连接集群${NC}"; exit 1; }
echo -e "${GREEN}✓ 集群连接正常${NC}"
echo ""

# -------------------------------
# 2. 边缘节点检查
echo -e "${YELLOW}[2/6] 检查边缘节点状态: ${EDGE_NODE}${NC}"
NODE_READY=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [ "$NODE_READY" != "True" ]; then
    echo -e "${RED}✗ 节点 ${EDGE_NODE} 未 Ready (当前: ${NODE_READY})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 节点 Ready${NC}"
echo ""

# -------------------------------
# 2b. 在边缘节点预拉镜像
echo -e "${YELLOW}[2b] 在边缘节点预拉镜像...${NC}"
echo -e "拉取 busybox 镜像..."
kubectl debug node/${EDGE_NODE} -it --image=busybox -- chroot /host sh -c "ctr -n k8s.io images pull docker.io/library/busybox:latest || true"
echo -e "拉取 n8nio/n8n 镜像..."
kubectl debug node/${EDGE_NODE} -it --image=busybox -- chroot /host sh -c "ctr -n k8s.io images pull docker.io/n8nio/n8n:latest || true"
echo -e "${GREEN}✓ 镜像拉取完成（或已存在）${NC}"
echo ""

# -------------------------------
# 3. 数据目录创建
echo -e "${YELLOW}[3/6] 创建/检查数据目录: ${STORAGE_PATH}${NC}"

kubectl run n8n-dir-check --restart=Never --image=busybox \
  --overrides="{
    \"spec\": {
      \"nodeName\": \"${EDGE_NODE}\",
      \"containers\":[{
        \"name\":\"check\",
        \"image\":\"busybox\",
        \"command\":[\"sh\",\"-c\",\"mkdir -p '${STORAGE_PATH}' && chmod 777 '${STORAGE_PATH}' && echo 'OK'\"] 
      }]
    }
  }"

# 呼吸感等待
echo -n "等待临时 Pod Ready "
for i in {1..12}; do
    sleep 5
    echo -n "."
done
echo
kubectl delete pod n8n-dir-check --force --grace-period=0 2>/dev/null
echo -e "${GREEN}✓ 数据目录创建完成${NC}"
echo ""

# -------------------------------
# 4. 创建 Service
echo -e "${YELLOW}[4/6] 创建 n8n Service...${NC}"
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
# 5. 创建 Deployment
echo -e "${YELLOW}[5/6] 创建 n8n Deployment...${NC}"
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

echo "Deployment 状态:"
kubectl get deployment n8n -o wide
echo ""

# -------------------------------
# 6. 等待 Pod Ready（带呼吸点）
echo -e "${YELLOW}[6/6] 等待 n8n Pod 就绪...${NC}"
POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}')

echo -n "等待 Pod Ready "
while true; do
    STATUS=$(kubectl get pod ${POD_NAME} -o jsonpath='{.status.phase}')
    if [ "$STATUS" == "Running" ]; then
        echo -e "\n${GREEN}✓ Pod 已就绪${NC}"
        break
    elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Unknown" ]; then
        echo -e "\n${RED}✗ Pod 状态异常: $STATUS${NC}"
        kubectl describe pod ${POD_NAME}
        exit 1
    else
        echo -n "."
        sleep 5
    fi
done

echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
echo -e "${GREEN}n8n 部署完成！${NC}"
echo -e "${GREEN}Pod 名称: ${POD_NAME}${NC}"
echo -e "${GREEN}访问地址: http://${NODE_IP}:${NODEPORT}${NC}"
echo -e "${GREEN}查看日志: kubectl logs -f ${POD_NAME}${NC}"
echo -e "${GREEN}查看 Pod: kubectl get pods -l app=n8n -o wide${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
