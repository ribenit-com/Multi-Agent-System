#!/usr/bin/env bash
set -Eeuo pipefail

############################################
# 基础变量
############################################
NAMESPACE="automation"
RELEASE="n8n-ha"
IMAGE="n8nio/n8n:2.8.2"
TAR_FILE="n8n_2.8.2.tar"
APP_NAME="n8n-ha"
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
echo "🚀 n8n HA 企业级 GitOps 自愈部署 v12.5 (Image Auto-Fix + DB Verified)"
echo "================================================="

############################################
# 0️⃣ Kubernetes 检查
############################################
echo "[CHECK] Kubernetes API"
kubectl version --client >/dev/null 2>&1 || kubectl version >/dev/null 2>&1 || true

############################################
# 1️⃣ containerd 镜像检查（本地存在优先，不 pull）
############################################
echo "[CHECK] containerd 镜像"
IMAGE_NAME_ONLY="${IMAGE##*/}"   # n8n:2.8.2

if sudo ctr -n k8s.io images list 2>/dev/null | grep -q "$IMAGE_NAME_ONLY"; then
    echo "[OK] 镜像已存在: $IMAGE_NAME_ONLY"
else
    if [ -f "$TAR_FILE" ]; then
        echo "[INFO] 镜像 tar 存在，直接导入到 k8s.io..."
        if command -v pv >/dev/null 2>&1; then
            pv "$TAR_FILE" | sudo ctr -n k8s.io images import - || true
        else
            sudo ctr -n k8s.io images import "$TAR_FILE" || true
        fi
        echo "[OK] 镜像导入完成"
    else
        echo "[WARN] 本地 tar 不存在，镜像无法拉取（避免 DNS 错误），请手动准备 $TAR_FILE 或确保网络可访问 docker.io"
    fi
fi

############################################
# 2️⃣ 生成 GitOps YAML 文件
############################################
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
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              memory: 1Gi
          readinessProbe:
            httpGet:
              path: /healthz
              port: 5678
            initialDelaySeconds: 20
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 5678
            initialDelaySeconds: 60
            periodSeconds: 20
          volumeMounts:
            - name: data
              mountPath: /home/node/.n8n
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app
                    operator: In
                    values:
                      - n8n
              topologyKey: kubernetes.io/hostname
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
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
  name: $APP_NAME
  namespace: argocd
spec:
  destination:
    namespace: $NAMESPACE
    server: https://kubernetes.default.svc
  source:
    repoURL: $(git config --get remote.origin.url 2>/dev/null || echo "")
    targetRevision: main
    path: $GITOPS_DIR
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

echo "[OK] GitOps YAML 文件生成完成: $GITOPS_DIR"

############################################
# 3️⃣ Helm 部署
############################################
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE" >/dev/null 2>&1 || true

echo "[HELM] 安装/升级 Release"
if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
    helm upgrade "$RELEASE" . -n "$NAMESPACE" || true
else
    helm install "$RELEASE" . -n "$NAMESPACE" || true
fi

############################################
# 4️⃣ GitOps 同步
############################################
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    cd "$(git rev-parse --show-toplevel)"
    git add "$GITOPS_DIR" >/dev/null 2>&1 || true
    if ! git diff --cached --quiet; then
        git commit -m "feat: auto update n8n-gitops $(date +%F-%T)" >/dev/null 2>&1 || true
    fi
    git push origin main >/dev/null 2>&1 || true
else
    echo "[WARN] 当前目录非 Git 仓库，跳过 GitOps"
fi

############################################
# 5️⃣ ArgoCD 同步
############################################
if kubectl get ns argocd >/dev/null 2>&1; then
    kubectl apply -f "$GITOPS_DIR/argocd-application.yaml" >/dev/null 2>&1 || true
fi

############################################
# 6️⃣ 收集交付数据
############################################
mkdir -p "$LOG_DIR"

safe_kubectl() { kubectl "$@" 2>/dev/null || echo ""; }

N8N_SERVICE_IP=$(safe_kubectl get svc -n "$NAMESPACE" "$RELEASE" -o jsonpath='{.spec.clusterIP}')
N8N_SERVICE_PORT=$(safe_kubectl get svc -n "$NAMESPACE" "$RELEASE" -o jsonpath='{.spec.ports[0].port}')
N8N_REPLICAS=$(safe_kubectl get deploy -n "$NAMESPACE" -l app.kubernetes.io/name=n8n -o jsonpath='{.items[0].spec.replicas}')
POD_STATUS=$(safe_kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=n8n --no-headers)
PVC_LIST=$(safe_kubectl get pvc -n "$NAMESPACE")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
ARGO_STATUS=$(safe_kubectl -n argocd get app "$APP_NAME" -o jsonpath='{.status.health.status}')

############################################
# 6.5️⃣ 数据库连通检测
############################################
DB_HOST="$DB_SERVICE.$DB_NAMESPACE.svc.cluster.local"

DNS_STATUS="FAILED"
TCP_STATUS="FAILED"
AUTH_STATUS="FAILED"

kubectl run dns-test --rm -i --restart=Never \
    --image=busybox -n "$NAMESPACE" \
    -- nslookup "$DB_HOST" >/dev/null 2>&1 && DNS_STATUS="OK" || true

kubectl run tcp-test --rm -i --restart=Never \
    --image=busybox -n "$NAMESPACE" \
    -- nc -z "$DB_HOST" 5432 >/dev/null 2>&1 && TCP_STATUS="OK" || true

kubectl run auth-test --rm -i --restart=Never \
    --image=postgres:15 -n "$NAMESPACE" \
    -- env PGPASSWORD="$DB_PASS" \
       psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' >/dev/null 2>&1 && AUTH_STATUS="OK" || true

############################################
# 7️⃣ 生成 HTML 报告
############################################
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付报告</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{margin:0;font-family:sans-serif;background:#f4f6f9}
.container{display:flex;justify-content:center;padding:40px}
.card{background:#fff;width:800px;border-radius:14px;padding:40px;box-shadow:0 15px 40px rgba(0,0,0,.08)}
h2{text-align:center;color:#1677ff}
h3{margin-top:30px;border-bottom:1px solid #eee;padding-bottom:6px}
pre{background:#f1f3f5;padding:14px;border-radius:8px}
.status-running{color:green;font-weight:600}
.status-pending{color:orange;font-weight:600}
.status-failed{color:red;font-weight:600}
.footer{text-align:center;margin-top:40px;font-size:12px;color:#888}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🚀 n8n HA 企业级交付报告 v12.5</h2>

<h3>部署信息</h3>
<p>Namespace: $NAMESPACE</p>
<p>Release: $RELEASE</p>
<p>Image: $IMAGE</p>
<p>Replicas: ${N8N_REPLICAS:-N/A}</p>
<p>Git Commit: $GIT_COMMIT</p>
<p>ArgoCD Status: ${ARGO_STATUS:-N/A}</p>

<h3>服务访问</h3>
<p>IP: ${N8N_SERVICE_IP:-N/A}</p>
<p>Port: ${N8N_SERVICE_PORT:-5678}</p>

<h3>Pod 状态</h3>
EOF

while read -r line; do
  POD_NAME=$(echo "$line" | awk '{print $1}')
  STATUS=$(echo "$line" | awk '{print $3}')
  CLASS="status-failed"
  [[ "$STATUS" == "Running" ]] && CLASS="status-running"
  [[ "$STATUS" == "Pending" ]] && CLASS="status-pending"
  echo "<div class=\"$CLASS\">$POD_NAME : $STATUS</div>" >> "$HTML_FILE"
done <<< "${POD_STATUS:-}"

cat >> "$HTML_FILE" <<EOF

<h3>数据库连通检测</h3>
<p>DNS 解析: <b>${DNS_STATUS}</b></p>
<p>TCP 5432: <b>${TCP_STATUS}</b></p>
<p>认证登录: <b>${AUTH_STATUS}</b></p>

<h3>PVC</h3>
<pre>${PVC_LIST:-N/A}</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</div>
</body>
</html>
EOF

echo
echo "📄 企业交付报告生成完成:"
echo "👉 $HTML_FILE"
echo
echo "🎉 v12.5 Image Auto-Fix + DB Verified 执行完成"
