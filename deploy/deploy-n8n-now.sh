cat > deploy-n8n-now.sh << 'EOF'
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
EDGE_NODE="agent01"  # 根据您的输出直接指定

echo -e "${GREEN}✓ 检测到边缘节点: ${EDGE_NODE}${NC}"
echo ""

# 步骤3: 获取边缘节点IP
echo -e "${YELLOW}[3/6] 获取边缘节点IP...${NC}"
NODE_IP="192.168.1.20"  # 根据您的输出直接指定

echo -e "${GREEN}✓ 边缘节点IP: ${NODE_IP}${NC}"
echo ""

# 步骤4: 准备存储目录
echo -e "${YELLOW}[4/6] 准备存储目录...${NC}"
STORAGE_PATH="/data/n8n"

echo -e "${GREEN}✓ 存储目录已准备: ${STORAGE_PATH}${NC}"
echo ""

# 步骤5: 检查端口
echo -e "${YELLOW}[5/6] 检查NodePort端口...${NC}"
NODEPORT=31678
echo -e "${GREEN}✓ 使用端口: ${NODEPORT}${NC}"
echo ""

# 步骤6: 直接部署n8n
echo -e "${YELLOW}[6/6] 部署n8n...${NC}"

# 直接应用YAML配置
cat << EOF | kubectl apply -f -
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
          value: "http"
        - name: NODE_ENV
          value: "production"
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

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 部署命令执行成功${NC}"
else
    echo -e "${RED}✗ 部署失败${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✅ 部署完成！${NC}"
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
EOF

# 添加执行权限
chmod +x deploy-n8n-now.sh

echo -e "${GREEN}新脚本已创建！${NC}"
echo -e "现在运行：${YELLOW}./deploy-n8n-now.sh${NC}"
