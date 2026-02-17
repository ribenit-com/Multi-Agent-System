# 创建全新的部署脚本
cat > deploy-n8n-new.sh << 'EOF'
#!/bin/bash

# ============================================
# n8n 全新一键部署脚本 (KubeEdge + Containerd)
# 版本: 3.0.0
# 执行位置: 控制中心 (.10)
# 说明: 这是一个完全独立的脚本，不依赖任何其他文件
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 设置边缘节点信息（请根据实际情况修改）
EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
NODEPORT=31678

# 打印标题
clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           n8n 全新一键部署脚本                            ║${NC}"
echo -e "${BLUE}║               版本: 3.0.0 - 独立版                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- 步骤1: 环境检查 ---
echo -e "${YELLOW}[1/4] 检查部署环境...${NC}"

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl 未安装，请在控制中心安装 kubectl${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 已安装${NC}"

# 检查集群连接
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}✗ 无法连接到 Kubernetes 集群${NC}"
    echo "请检查:"
    echo "  - kubeconfig 配置是否正确"
    echo "  - 集群是否正常运行"
    exit 1
fi
echo -e "${GREEN}✓ 集群连接正常${NC}"

# 检查边缘节点是否存在
if ! kubectl get node ${EDGE_NODE} &> /dev/null; then
    echo -e "${YELLOW}⚠ 边缘节点 ${EDGE_NODE} 不存在，查看可用节点:${NC}"
    kubectl get nodes
    echo ""
    read -p "请输入正确的边缘节点名称: " EDGE_NODE
fi
echo -e "${GREEN}✓ 目标边缘节点: ${EDGE_NODE}${NC}"
echo ""

# --- 步骤2: 直接在边缘节点创建数据目录（通过SSH） ---
echo -e "${YELLOW}[2/4] 在边缘节点 ${EDGE_NODE} 上创建数据目录...${NC}"

STORAGE_PATH="/data/n8n"

# 直接在边缘节点上创建目录（假设SSH免密登录已配置）
echo "尝试通过SSH在边缘节点创建目录..."
ssh -o ConnectTimeout=5 ${EDGE_NODE} "sudo mkdir -p ${STORAGE_PATH} && sudo chmod 777 ${STORAGE_PATH}" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ SSH连接成功，数据目录已创建${NC}"
else
    echo -e "${YELLOW}⚠ SSH连接失败，尝试使用临时Pod创建目录...${NC}"
    
    # 如果SSH失败，使用临时Pod创建目录
    cat << EOF | kubectl apply -f - > /dev/null
apiVersion: v1
kind: Pod
metadata:
  name: n8n-dir-prepare
  namespace: default
spec:
  nodeName: ${EDGE_NODE}
  containers:
  - name: prepare
    image: busybox:latest
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
EOF
    
    echo "等待目录创建完成..."
    sleep 5
    kubectl delete pod n8n-dir-prepare --force --grace-period=0 > /dev/null 2>&1
    echo -e "${GREEN}✓ 数据目录已创建${NC}"
fi
echo ""

# --- 步骤3: 部署n8n ---
echo -e "${YELLOW}[3/4] 部署 n8n 到 KubeEdge 集群...${NC}"

# 先删除可能存在的旧部署
kubectl delete deployment n8n --ignore-not-found > /dev/null 2>&1
kubectl delete svc n8n-service --ignore-not-found > /dev/null 2>&1
sleep 2

# 直接应用YAML配置（不生成中间文件）
cat << EOF | kubectl apply -f -
---
apiVersion: v1
kind: Service
metadata:
  name: n8n-service
  namespace: default
  labels:
    app: n8n
spec:
  type: NodePort
  ports:
  - port: 5678
    targetPort: 5678
    nodePort: ${NODEPORT}
    protocol: TCP
    name: http
  selector:
    app: n8n
---
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
      tolerations:
      - key: "node-role.kubernetes.io/edge"
        operator: "Exists"
        effect: "NoSchedule"
      - key: "node.kubernetes.io/not-ready"
        operator: "Exists"
        effect: "NoExecute"
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        imagePullPolicy: Always
        ports:
        - containerPort: 5678
          name: web
        env:
        - name: N8N_PORT
          value: "5678"
        - name: N8N_PROTOCOL
          value: "http"
        - name: NODE_ENV
          value: "production"
        - name: N8N_HOST
          value: "${NODE_IP}"
        - name: WEBHOOK_URL
          value: "http://${NODE_IP}:${NODEPORT}"
        - name: GENERIC_TIMEZONE
          value: "Asia/Shanghai"
        volumeMounts:
        - name: n8n-data
          mountPath: /home/node/.n8n
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 6
        readinessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 20
          periodSeconds: 5
          timeoutSeconds: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: n8n-data
        hostPath:
          path: ${STORAGE_PATH}
          type: DirectoryOrCreate
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 部署命令执行成功${NC}"
else
    echo -e "${RED}✗ 部署失败${NC}"
    exit 1
fi
echo ""

# --- 步骤4: 等待并验证 ---
echo -e "${YELLOW}[4/4] 等待 Pod 启动并验证...${NC}"

# 等待 Pod 调度
echo "等待 Pod 调度到边缘节点 (最多60秒)..."
for i in {1..12}; do
    POD_STATUS=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" == "Running" ]; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# 获取最终状态
POD_NAME=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
POD_STATUS=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
POD_NODE=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)

if [ "$POD_STATUS" == "Running" ]; then
    echo -e "${GREEN}✓ Pod 运行成功${NC}"
    echo -e "  ${BLUE}•${NC} Pod名称: ${POD_NAME}"
    echo -e "  ${BLUE}•${NC} 状态: ${GREEN}Running${NC}"
    echo -e "  ${BLUE}•${NC} 所在节点: ${POD_NODE}"
else
    echo -e "${YELLOW}⚠ Pod 状态: ${POD_STATUS:-Pending}${NC}"
    echo "查看详细状态: kubectl describe pod -l app=n8n"
fi

# 显示服务信息
SVC_INFO=$(kubectl get svc n8n-service -o wide 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Service 已创建${NC}"
fi

# 完成信息
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}              n8n 部署完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}📦 部署信息${NC}"
echo -e "  ${BLUE}•${NC} 边缘节点:    ${GREEN}${EDGE_NODE}${NC}"
echo -e "  ${BLUE}•${NC} 节点 IP:      ${GREEN}${NODE_IP}${NC}"
echo -e "  ${BLUE}•${NC} 访问端口:     ${GREEN}${NODEPORT}${NC}"
echo -e "  ${BLUE}•${NC} 数据目录:     ${GREEN}${STORAGE_PATH}${NC}"
echo ""
echo -e "${CYAN}🌐 访问地址${NC}"
echo -e "  ${BLUE}•${NC} 本地访问:     ${GREEN}http://localhost:5678${NC} (在边缘节点)"
echo -e "  ${BLUE}•${NC} NodePort访问: ${GREEN}http://${NODE_IP}:${NODEPORT}${NC}"
echo ""
echo -e "${CYAN}🔧 管理命令${NC}"
echo -e "  ${BLUE}•${NC} 查看 Pod:     ${YELLOW}kubectl get pods -l app=n8n -o wide${NC}"
echo -e "  ${BLUE}•${NC} 查看日志:     ${YELLOW}kubectl logs -f -l app=n8n${NC}"
echo -e "  ${BLUE}•${NC} 重启部署:     ${YELLOW}kubectl rollout restart deployment n8n${NC}"
echo ""

# 询问是否查看日志
read -p "是否查看实时日志？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}显示日志 (按 Ctrl+C 退出)${NC}"
    sleep 2
    kubectl logs -f -l app=n8n
fi

echo -e "${GREEN}✅ 脚本执行完毕！${NC}"
EOF

# 给脚本添加执行权限
chmod +x deploy-n8n-new.sh

echo -e "${GREEN}✅ 全新的独立脚本已创建！${NC}"
echo -e "${YELLOW}现在运行：${NC} ./deploy-n8n-new.sh"
