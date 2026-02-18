#!/bin/bash
set -e

# --------------------------
# 一键生成 PostgreSQL HA Helm Chart + ArgoCD Application + PV
# 自动清理冲突 PVC/PV/StorageClass
# --------------------------

# 配置
CHART_DIR="$HOME/gitops/postgres-ha-chart"
NAMESPACE="database"
ARGO_APP="postgres-ha"
GITHUB_REPO="ribenit-com/Multi-Agent-k8s-gitops-postgres"
PVC_SIZE="10Gi"
APP_LABEL="postgres"

echo "=== Step 0: 清理已有冲突 PVC/PV ==="
# 删除同名 PVC
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
# 删除同名 PV
kubectl get pv -o name | grep postgres-pv- | xargs -r kubectl delete

echo "=== Step 1: 检测集群 StorageClass ==="
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)
if [ -z "$SC_NAME" ]; then
  echo "⚠️ 集群没有 StorageClass，将不指定 StorageClass，并创建手动 PV"
else
  echo "✅ 检测到 StorageClass: $SC_NAME"
fi

echo "=== Step 2: 创建 Helm Chart 目录 ==="
mkdir -p "$CHART_DIR/templates"

echo "=== Step 3: 写入 Chart.yaml ==="
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: postgres-ha-chart
description: "Official PostgreSQL 16.3 Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "16.3"
EOF

echo "=== Step 4: 写入 values.yaml ==="
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

echo "=== Step 5: 写入 templates/statefulset.yaml ==="
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

echo "=== Step 6: 写入 templates/service.yaml ==="
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

echo "=== Step 7: 写入 templates/headless-service.yaml ==="
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

# Step 8: 如果没有 StorageClass，自动创建 PV
if [ -z "$SC_NAME" ]; then
  echo "=== Step 8: 创建手动 PV ==="
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

echo "=== Step 9: 应用 ArgoCD Application ==="
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

echo "=== 完成：PostgreSQL HA Helm Chart + ArgoCD Application 已生成并应用 ==="
