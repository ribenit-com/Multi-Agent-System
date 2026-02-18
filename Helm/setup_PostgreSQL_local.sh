#!/bin/bash
set -Eeuo pipefail

# ===================================================
# PostgreSQL HA 企业级一键部署 + HTML 交付页面
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/postgres-ha-chart"
NAMESPACE="database"
ARGO_APP="postgres-ha"
GITHUB_REPO="ribenit-com/Multi-Agent-k8s-gitops-postgres"
PVC_SIZE="10Gi"
APP_LABEL="postgres"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/postgres_ha_info.html"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
kubectl get pv -o name | grep postgres-pv- | xargs -r kubectl delete || true

# ---------- Step 1: 检测 StorageClass ----------
echo "=== Step 1: 检测 StorageClass ==="
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  echo "⚠️ 集群没有 StorageClass，将使用手动 PV"
else
  echo "✅ 检测到 StorageClass: $SC_NAME"
fi

# ---------- Step 2: 创建 Helm Chart ----------
echo "=== Step 2: 创建 Helm Chart ==="

# Chart.yaml
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: postgres-ha-chart
description: "Official PostgreSQL 16.3 Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "16.3"
EOF

# values.yaml
cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2

image:
  registry: docker.m.daocloud.io
  repository: library/postgres
  tag: "16.3"
  pullPolicy: IfNotPresent

postgresql:
  username: myuser
  password: mypassword
  database: mydb

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

ha:
  enabled: true
  synchronousCommit: "on"
  replicationMode: "asynchronous"
EOF

# templates/statefulset.yaml
cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  serviceName: postgres-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: POSTGRES_USER
              value: {{ .Values.postgresql.username | quote }}
            - name: POSTGRES_PASSWORD
              value: {{ .Values.postgresql.password | quote }}
            - name: POSTGRES_DB
              value: {{ .Values.postgresql.database | quote }}
          ports:
            - containerPort: 5432
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: {{ .Values.persistence.size }}
        {{- if .Values.persistence.storageClass }}
        storageClassName: {{ .Values.persistence.storageClass }}
        {{- end }}
EOF

# templates/service.yaml
cat > "$CHART_DIR/templates/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
      name: postgres
  selector:
    app: postgres
EOF

# templates/headless-service.yaml
cat > "$CHART_DIR/templates/headless-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None
  ports:
    - port: 5432
      targetPort: 5432
  selector:
    app: postgres
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="postgres-pv-$i"
    mkdir -p /mnt/data/postgres-$i
    cat > /tmp/$PV_NAME.yaml <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
spec:
  capacity:
    storage: $PVC_SIZE
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /mnt/data/postgres-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: 应用 ArgoCD Application ----------
echo "=== Step 4: 应用 ArgoCD Application ==="
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $ARGO_APP
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/$GITHUB_REPO.git'
    targetRevision: main
    path: postgres-ha-chart
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: $NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# ---------- Step 4a: 等待 ArgoCD 同步 ----------
echo "等待 ArgoCD Application 同步完成..."
for i in {1..60}; do
  STATUS=$(kubectl -n argocd get app $ARGO_APP -o jsonpath='{.status.sync.status}' || echo "")
  HEALTH=$(kubectl -n argocd get app $ARGO_APP -o jsonpath='{.status.health.status}' || echo "")
  echo "[$i] ArgoCD sync=$STATUS, health=$HEALTH"
  if [[ "$STATUS" == "Synced" && "$HEALTH" == "Healthy" ]]; then
    echo "✅ ArgoCD Application 已同步完成"
    break
  fi
  sleep 5
done

# ---------- Step 4b: 检查 StatefulSet ----------
echo "检查 StatefulSet..."
kubectl -n $NAMESPACE get sts -o wide || echo "⚠ 没有找到 StatefulSet"

if kubectl -n $NAMESPACE get sts $APP_LABEL >/dev/null 2>&1; then
  echo "等待 PostgreSQL StatefulSet 就绪..."
  kubectl -n $NAMESPACE rollout status sts/$APP_LABEL --timeout=300s
else
  echo "❌ StatefulSet $APP_LABEL 不存在，请检查 Helm Chart 或 ArgoCD 日志"
  echo "查看 ArgoCD controller 日志: kubectl -n argocd logs deploy/argocd-application-controller"
  exit 1
fi

# ---------- Step 5: 生成企业交付 HTML ----------
echo "=== Step 5: 生成 HTML 页面 ==="
SERVICE_IP=$(kubectl -n $NAMESPACE get svc $APP_LABEL -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
NODE_PORT=$(kubectl -n $NAMESPACE get svc $APP_LABEL -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

DB_USER="myuser"
DB_PASSWORD="mypassword"
DB_NAME="mydb"
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts $APP_LABEL -o jsonpath='{.spec.replicas}' || echo "2")

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head><meta charset="UTF-8"><title>PostgreSQL HA 企业交付指南</title></head>
<body>
<h2>🎉 PostgreSQL HA 安装完成</h2>
<h3>数据库信息</h3>
Namespace: $NAMESPACE<br>
Service: $APP_LABEL<br>
ClusterIP: $SERVICE_IP<br>
NodePort: ${NODE_PORT:-N/A}<br>
用户名: $DB_USER<br>
密码: $DB_PASSWORD<br>
数据库: $DB_NAME<br>
副本数: $REPLICA_COUNT<br>
<h3>PVC 列表</h3>
<pre>$PVC_LIST</pre>
<h3>访问方式</h3>
kubectl -n $NAMESPACE port-forward svc/$APP_LABEL 5432:5432<br>
psql -h localhost -U $DB_USER -d $DB_NAME<br>
<h3>Python 示例</h3>
<pre>
import psycopg2
conn = psycopg2.connect(
    host="$SERVICE_IP",
    database="$DB_NAME",
    user="$DB_USER",
    password="$DB_PASSWORD"
)
cur = conn.cursor()
cur.execute("SELECT version();")
print(cur.fetchone())
</pre>
<h3>Java 示例</h3>
<pre>
String url = "jdbc:postgresql://$SERVICE_IP:5432/$DB_NAME";
Properties props = new Properties();
props.setProperty("user","$DB_USER");
props.setProperty("password","$DB_PASSWORD");
Connection conn = DriverManager.getConnection(url, props);
</pre>
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</body>
</html>
EOF

echo "✅ PostgreSQL HA 企业交付 HTML 页面已生成: $HTML_FILE"
