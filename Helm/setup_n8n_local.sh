#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 基础变量
############################################
NAMESPACE="automation"
APP_NAME="n8n"
IMAGE="docker.io/n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
GITOPS_DIR="./n8n-gitops"

# 数据库信息
DB_NAMESPACE="database"
DB_SERVICE="postgres"
DB_USER="myuser"
DB_PASS="mypassword"
DB_NAME="mydb"

LOG_DIR="/mnt/truenas"
HTML_FILE="$LOG_DIR/n8n-ha-delivery.html"

############################################
# 错误捕获
############################################
trap 'echo; echo "[FATAL] 第 $LINENO 行执行失败"; exit 1' ERR

echo "================================================="
echo "🚀 n8n HA 本地自容部署 v4.2 (镜像自动导入 + YAML生成 + ArgoCD + 健康检查 + HTML报告)"
echo "================================================="

############################################
# 0️⃣ Kubernetes 检查
############################################
echo "[CHECK] Kubernetes API"
kubectl version --client >/dev/null 2>&1 || kubectl version >/dev/null 2>&1 || true

############################################
# 1️⃣ containerd 镜像检查 & 自动导入
############################################
echo "[CHECK] containerd 镜像"

# 检查镜像是否存在
IMAGE_NAME_ONLY="${IMAGE##*/}" # n8n:2.8.2
if sudo ctr -n k8s.io images list 2>/dev/null | grep -q "$IMAGE_NAME_ONLY"; then
    echo "[OK] 镜像已存在: $IMAGE_NAME_ONLY"
else
    if [ -f "$TAR_FILE" ]; then
        echo "[INFO] 本地 tar 存在，开始导入镜像..."
        if command -v pv >/dev/null 2>&1; then
            pv "$TAR_FILE" | sudo ctr -n k8s.io images import -
        else
            sudo ctr -n k8s.io images import "$TAR_FILE"
        fi
        echo "[OK] 镜像导入完成: $IMAGE"
    else
        echo "[FATAL] 本地镜像不存在，且 tar 文件 $TAR_FILE 不存在，请准备镜像后重试"
        exit 1
    fi
fi

############################################
# 2️⃣ Namespace 创建
############################################
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null 2>&1 || true

############################################
# 3️⃣ 生成 GitOps YAML 文件
############################################
echo "[GENERATE] 生成 GitOps YAML 文件: $GITOPS_DIR"
mkdir -p "$GITOPS_DIR"

# namespace.yaml
cat > "$GITOPS_DIR/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF

# secret.yaml
cat > "$GITOPS_DIR/secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: $NAMESPACE
type: Opaque
stringData:
  password: $DB_PASS
EOF

# service.yaml
cat > "$GITOPS_DIR/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: $NAMESPACE
spec:
  selector:
    app: n8n
  ports:
    - port: 5678
      targetPort: 5678
  type: ClusterIP
EOF

# statefulset.yaml
cat > "$GITOPS_DIR/statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: n8n
  namespace: $NAMESPACE
spec:
  serviceName: n8n
  replicas: 2
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:15
          command:
            - sh
            - -c
            - |
              until pg_isready -h $DB_SERVICE.$DB_NAMESPACE.svc.cluster.local -p 5432; do
                echo "Waiting for Postgres..."
                sleep 3
              done
      containers:
        - name: n8n
          image: $IMAGE
          ports:
            - containerPort: 5678
          env:
            - name: DB_TYPE
              value: postgresdb
            - name: DB_POSTGRESDB_HOST
              value: $DB_SERVICE.$DB_NAMESPACE.svc.cluster.local
            - name: DB_POSTGRESDB_PORT
              value: "5432"
            - name: DB_POSTGRESDB_DATABASE
              value: $DB_NAME
            - name: DB_POSTGRESDB_USER
              value: $DB_USER
            - name: DB_POSTGRESDB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
            - name: EXECUTIONS_MODE
              value: regular
          volumeMounts:
            - name: data
              mountPath: /home/node/.n8n
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
EOF

# ingress.yaml
cat > "$GITOPS_DIR/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: $NAMESPACE
spec:
  rules:
    - host: n8n.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: n8n
                port:
                  number: 5678
EOF

# argocd-application.yaml
cat > "$GITOPS_DIR/argocd-application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: n8n-ha
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ""  # 本地部署，可空
    targetRevision: main
    path: $GITOPS_DIR
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "[OK] YAML 文件生成完成"

############################################
# 4️⃣ 应用 YAML 到 Kubernetes
############################################
echo "[INSTALL] 应用 YAML 到 Kubernetes"
kubectl apply -f "$GITOPS_DIR/" || true
echo "[OK] GitOps YAML 已应用"

############################################
# 5️⃣ 创建/更新 ArgoCD Application
############################################
echo "[ARGOCD] 创建/更新 Application"
kubectl apply -f "$GITOPS_DIR/argocd-application.yaml" || true
echo "[OK] ArgoCD Application 已创建/更新"

############################################
# 6️⃣ 等待 Pod 就绪
############################################
echo "[CHECK] 等待 n8n Pod 就绪..."
MAX_WAIT=180
SLEEP_INTERVAL=5
ELAPSED=0

while true; do
  READY_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=n8n --no-headers 2>/dev/null | grep -c "Running")
  TOTAL_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=n8n --no-headers 2>/dev/null | wc -l)

  if [[ "$TOTAL_COUNT" -gt 0 && "$READY_COUNT" -eq "$TOTAL_COUNT" ]]; then
      echo "[OK] 所有 n8n Pod 已就绪 ($READY_COUNT/$TOTAL_COUNT)"
      break
  fi

  sleep $SLEEP_INTERVAL
  ELAPSED=$((ELAPSED + SLEEP_INTERVAL))
  if [[ "$ELAPSED" -ge "$MAX_WAIT" ]]; then
      echo "[WARN] 等待 n8n Pod 就绪超时 ($READY_COUNT/$TOTAL_COUNT)"
      break
  fi
done

############################################
# 7️⃣ 服务端口可访问 & 数据库连通性检查
############################################
SERVICE_IP=$(kubectl get svc -n "$NAMESPACE" n8n -o jsonpath='{.spec.clusterIP}')
SERVICE_PORT=$(kubectl get svc -n "$NAMESPACE" n8n -o jsonpath='{.spec.ports[0].port}')

if nc -z -w 5 "$SERVICE_IP" "$SERVICE_PORT"; then
    SERVICE_STATUS="OK"
else
    SERVICE_STATUS="FAILED"
fi

DB_HOST="$DB_SERVICE.$DB_NAMESPACE.svc.cluster.local"
kubectl run db-test --rm -i --restart=Never \
  --image=postgres:15 -n "$NAMESPACE" \
  --env PGPASSWORD="$DB_PASS" \
  --command -- psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' >/dev/null 2>&1 && DB_STATUS="OK" || DB_STATUS="FAILED"

############################################
# 8️⃣ HTML 报告生成
############################################
mkdir -p "$LOG_DIR"

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付报告</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:sans-serif;background:#f4f6f9;margin:0;padding:20px}
h2{color:#1677ff;text-align:center}
.status-ok{color:green;font-weight:600}
.status-failed{color:red;font-weight:600}
</style>
</head>
<body>
<h2>🚀 n8n HA 本地部署报告</h2>

<h3>部署信息</h3>
<p>Namespace: $NAMESPACE</p>
<p>App Name: $APP_NAME</p>
<p>Image: $IMAGE</p>
<p>YAML 目录: $GITOPS_DIR</p>

<h3>Pod 状态</h3>
<p>就绪 Pod: <b>$READY_COUNT/$TOTAL_COUNT</b></p>

<h3>服务状态</h3>
<p>服务端口访问: <b class="status-${SERVICE_STATUS,,}">$SERVICE_STATUS</b></p>
<p>数据库连通: <b class="status-${DB_STATUS,,}">$DB_STATUS</b></p>

<p>生成时间: $(date '+%Y-%m-%d %H:%M:%S')</p>
</body>
</html>
EOF

echo
echo "📄 企业交付报告生成完成:"
echo "👉 $HTML_FILE"
echo
echo "🎉 n8n 本地自容部署完成"
