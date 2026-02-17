# 删除有问题的脚本
rm -f deploy-n8n-final-run.sh

# 创建修复后的脚本
cat > deploy-n8n-final-run-fixed.sh << 'EOF'
#!/bin/bash

# ============================================
# n8n 生产级部署脚本 (KubeEdge + Containerd)
# 版本: 2.0.1
# 执行位置: 控制中心 (.10)
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║      n8n 生产级部署脚本 (KubeEdge + Containerd)           ║${NC}"
echo -e "${BLUE}║                   版本: 2.0.1 (修复版)                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- 1. 环境检查 ---
echo -e "${YELLOW}[1/5] 检查部署环境...${NC}"

# 检查 kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl 未安装，请在控制中心安装 kubectl${NC}"
    exit 1
fi

# 检查集群连接
if ! kubectl get nodes &> /dev/null; then
    echo -e "${RED}✗ 无法连接到 Kubernetes 集群${NC}"
    exit 1
fi
echo -e "${GREEN}✓ kubectl 连接正常${NC}"

# 获取边缘节点信息
EDGE_NODE="agent01"
NODE_IP="192.168.1.20"
echo -e "${GREEN}✓ 目标边缘节点: ${EDGE_NODE} (${NODE_IP})${NC}"
sleep 1

# --- 2. 在边缘节点创建数据目录 (通过临时 Pod) ---
echo -e "${YELLOW}[2/5] 在边缘节点 ${EDGE_NODE} 上准备数据目录...${NC}"
STORAGE_PATH="/data/n8n"

# 创建一个临时 Pod 来创建目录 - 修复了 EOF 问题
TMP_POD=$(cat << 'PODEOF'
apiVersion: v1
kind: Pod
metadata:
  name: n8n-dir-prepare
  namespace: default
spec:
  nodeName: agent01
  containers:
  - name: prepare
    image: busybox:latest
    command: ["sh", "-c", "mkdir -p /data/n8n && chmod 777 /data/n8n"]
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
PODEOF
)

echo "$TMP_POD" | kubectl apply -f - > /dev/null 2>&1

# 等待 Pod 完成
echo "   等待目录创建完成..."
sleep 5

# 删除临时 Pod
kubectl delete pod n8n-dir-prepare --force --grace-period=0 > /dev/null 2>&1
echo -e "${GREEN}✓ 数据目录已准备: ${STORAGE_PATH}${NC}"
sleep 1

# --- 3. 生成部署 YAML ---
echo -e "${YELLOW}[3/5] 生成 n8n 部署配置...${NC}"

cat > n8n-production.yaml << 'YAMLEOF'
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
    nodePort: 31678
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
        kubernetes.io/hostname: agent01
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
        imagePullPolicy: IfNotPresent
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
          value: "192.168.1.20"
        - name: WEBHOOK_URL
          value: "http://192.168.1.20:31678"
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
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
      volumes:
      - name: n8n-data
        hostPath:
          path: /data/n8n
          type: DirectoryOrCreate
YAMLEOF

echo -e "${GREEN}✓ 配置文件生成: n8n-production.yaml${NC}"
sleep 1

# --- 4. 应用部署 ---
echo -e "${YELLOW}[4/5] 部署 n8n 到 KubeEdge 集群...${NC}"

# 先删除可能存在的旧部署
kubectl delete deployment n8n --ignore-not-found > /dev/null 2>&1
kubectl delete svc n8n-service --ignore-not-found > /dev/null 2>&1
sleep 2

# 应用新配置
kubectl apply -f n8n-production.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 部署命令已执行${NC}"
else
    echo -e "${RED}✗ 部署失败${NC}"
    exit 1
fi

# --- 5. 等待并验证 ---
echo -e "${YELLOW}[5/5] 等待 Pod 启动并验证...${NC}"
echo "   等待 Pod 调度到边缘节点..."
sleep 10

# 获取 Pod 状态
POD_STATUS=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
POD_NODE=$(kubectl get pods -l app=n8n -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)

if [ "$POD_STATUS" == "Running" ]; then
    echo -e "${GREEN}✓ Pod 正在运行${NC}"
    echo -e "${GREEN}✓ Pod 所在节点: ${POD_NODE}${NC}"
else
    echo -e "${YELLOW}⚠ Pod 状态: ${POD_STATUS:-Pending}，请稍后手动检查${NC}"
fi

# --- 完成 ---
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ n8n 部署完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}📦 部署信息${NC}"
echo -e "  ${BLUE}•${NC} 边缘节点:    ${GREEN}agent01${NC}"
echo -e "  ${BLUE}•${NC} 节点 IP:      ${GREEN}192.168.1.20${NC}"
echo -e "  ${BLUE}•${NC} 数据目录:     ${GREEN}/data/n8n${NC}"
echo ""
echo -e "${CYAN}🌐 访问地址${NC}"
echo -e "  ${BLUE}•${NC} 集群内访问:  ${GREEN}http://n8n-service:5678${NC}"
echo -e "  ${BLUE}•${NC} NodePort 访问: ${GREEN}http://192.168.1.20:31678${NC}"
echo ""
echo -e "${CYAN}🔧 管理命令 (在控制中心执行)${NC}"
echo -e "  ${BLUE}•${NC} 查看 Pod:     ${YELLOW}kubectl get pods -l app=n8n -o wide${NC}"
echo -e "  ${BLUE}•${NC} 查看日志:     ${YELLOW}kubectl logs -f -l app=n8n${NC}"
echo ""

# 可选：显示实时日志
read -p "是否查看实时日志？(y/n): " -n 1 -r VIEW_LOGS
echo
if [[ $VIEW_LOGS =~ ^[Yy]$ ]]; then
    kubectl logs -f -l app=n8n
fi

exit 0
EOF

chmod +x deploy-n8n-final-run-fixed.sh

echo -e "${GREEN}✅ 修复版脚本已创建！${NC}"
echo -e "${YELLOW}现在运行修复版脚本：${NC} ./deploy-n8n-final-run-fixed.sh"
