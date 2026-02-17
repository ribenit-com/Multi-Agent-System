cat > deploy-n8n-fixed.sh << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   n8n 一键自动部署脚本 (KubeEdge)${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 步骤1: 检查kubectl
echo -e "${YELLOW}[1/6] 检查kubectl连接状态...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl未安装${NC}"
    exit 1
fi

if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}✗ 无法连接到Kubernetes集群${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl连接正常${NC}"
echo ""

# 步骤2: 自动检测边缘节点
echo -e "${YELLOW}[2/6] 自动检测边缘节点...${NC}"
# 查找带有edge/agent标签的节点，如果没有则使用第一个非master节点
EDGE_NODE=$(kubectl get nodes --show-labels | grep -E "edge|agent|worker" | head -1 | awk '{print $1}')

if [ -z "$EDGE_NODE" ]; then
    # 如果没有找到带标签的节点，使用第一个非control-plane节点
    EDGE_NODE=$(kubectl get nodes | grep -v "control-plane" | grep -v "master" | awk 'NR>1 {print $1; exit}')
fi

if [ -z "$EDGE_NODE" ]; then
    # 如果还是没有，使用第一个节点
    EDGE_NODE=$(kubectl get nodes | awk 'NR>1 {print $1; exit}')
fi

if [ -z "$EDGE_NODE" ]; then
    echo -e "${RED}✗ 无法检测到边缘节点${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 检测到边缘节点: ${EDGE_NODE}${NC}"
echo ""

# 步骤3: 获取边缘节点IP
echo -e "${YELLOW}[3/6] 获取边缘节点IP...${NC}"
# 尝试多种方式获取节点IP
NODE_IP=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

if [ -z "$NODE_IP" ]; then
    # 如果没有InternalIP，尝试ExternalIP
    NODE_IP=$(kubectl get node ${EDGE_NODE} -o jsonpath='{.status.addresses[?(@.type=="ExternalIP")].address}')
fi

if [ -z "$NODE_IP" ]; then
    # 如果还是获取不到，提示手动输入
    echo -e "${YELLOW}无法自动获取节点IP，请输入边缘节点${EDGE_NODE}的IP地址:${NC}"
    read -p "IP地址: " NODE_IP
fi

if [ -z "$NODE_IP" ]; then
    echo -e "${RED}✗ 无法获取节点IP${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 边缘节点IP: ${NODE_IP}${NC}"
echo ""

# 步骤4: 检查并准备存储目录
echo -e "${YELLOW}[4/6] 准备存储目录...${NC}"
STORAGE_PATH="/data/n8n"

# 创建存储目录的临时Pod
cat << EOFS | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: n8n-prepare
  namespace: default
spec:
  nodeName: ${EDGE_NODE}
  containers:
  - name: prepare
    image: busybox
    command: ["sh", "-c", "mkdir -p ${STORAGE_PATH} && chmod 777 ${STORAGE_PATH}"]
    volumeMounts:
    - name: host-root
      mountPath: /host
    securityContext:
      privileged: true
  volumes:
  - name: host-root
    hostPath:
      path: /
  restartPolicy: Never
EOFS

# 等待Pod完成
sleep 5
kubectl delete pod n8n-prepare --force --grace-period=0 &> /dev/null

echo -e "${GREEN}✓ 存储目录已准备: ${STORAGE_PATH}${NC}"
echo ""

# 步骤5: 检查端口是否可用
echo -e "${YELLOW}[5/6] 检查NodePort端口...${NC}"
NODEPORT=31678
# 简单检查端口是否被占用（通过查看现有Service）
while kubectl get svc -A | grep -q ":${NODEPORT}/TCP"; do
    echo -e "${YELLOW}端口 ${NODEPORT} 已被占用，尝试下一个...${NC}"
    NODEPORT=$((NODEPORT + 1))
    if [ $NODEPORT -gt 32767 ]; then
        NODEPORT=30000
    fi
done
echo -e "${GREEN}✓ 使用端口: ${NODEPORT}${NC}"
echo ""

# 步骤6: 生成并部署n8n
echo -e "${YELLOW}[6/6] 生成n8n部署配置...${NC}"

# 创建最终的部署YAML
cat << EOF > n8n-deploy.yaml
# n8n部署配置 - 自动生成于 $(date)
# 边缘节点: ${EDGE_NODE} (${NODE_IP})
# 访问地址: http://${NODE_IP}:${NODEPORT}

apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: default
  labels:
    app: n8n
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
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        ports:
        - containerPort: 5678
        env:
        - name: N8N_PORT
          value: "5678"
        - name: N8N_PROTOCOL
          value: http
        - name: NODE_ENV
          value: production
        - name: WEBHOOK_URL
          value: "http://${NODE_IP}:5678"
        - name: N8N_HOST
          value: "${NODE_IP}"
        volumeMounts:
        - name: n8n-data
          mountPath: /home/node/.n8n
      volumes:
      - name: n8n-data
        hostPath:
          path: ${STORAGE_PATH}
---
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

if [ ! -f "n8n-deploy.yaml" ]; then
    echo -e "${RED}✗ 配置文件生成失败${NC}"
    exit 1
fi

echo -e "${GREEN}✓ 配置文件生成完成: n8n-deploy.yaml${NC}"
echo ""

# 部署
echo -e "${YELLOW}开始部署n8n...${NC}"
kubectl apply -f n8n-deploy.yaml

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 部署命令已执行！${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "部署信息摘要："
echo -e "  • 边缘节点: ${GREEN}${EDGE_NODE}${NC}"
echo -e "  • 节点IP: ${GREEN}${NODE_IP}${NC}"
echo -e "  • 访问端口: ${GREEN}${NODEPORT}${NC}"
echo -e "  • 存储路径: ${GREEN}${STORAGE_PATH}${NC}"
echo ""
echo -e "访问地址: ${GREEN}http://${NODE_IP}:${NODEPORT}${NC}"
echo ""
echo -e "${YELLOW}查看部署状态:${NC}"
echo "  kubectl get pods -l app=n8n -w"
echo "  kubectl logs -l app=n8n"
echo ""
echo -e "${YELLOW}如果Pod启动失败，查看详情:${NC}"
echo "  kubectl describe pod -l app=n8n"
echo ""
EOF

# 添加执行权限
chmod +x deploy-n8n-fixed.sh

echo -e "${GREEN}修复脚本已创建！${NC}"
echo -e "现在运行：${YELLOW}./deploy-n8n-fixed.sh${NC}"
