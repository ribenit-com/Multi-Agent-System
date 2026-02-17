# 创建n8n部署配置文件
cat << 'EOF' > n8n-deployment.yaml
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
        # 指定在边缘节点运行
        kubernetes.io/hostname: edge-node  # 如果边缘节点名称不同，请修改
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
          value: "http://边缘机IP:5678"  # 替换为实际的边缘节点IP
        - name: N8N_HOST
          value: "边缘机IP"  # 替换为实际的边缘节点IP
        volumeMounts:
        - name: n8n-data
          mountPath: /home/node/.n8n
      volumes:
      - name: n8n-data
        hostPath:
          path: /data/n8n  # 边缘节点上的存储路径
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
    nodePort: 31678  # 可以修改为未被占用的端口
  selector:
    app: n8n
EOF

# 部署n8n
kubectl apply -f n8n-deployment.yaml

# 查看部署状态
kubectl get pods -o wide | grep n8n
kubectl get svc n8n-service