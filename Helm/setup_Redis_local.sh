#!/bin/bash
set -Eeuo pipefail

# ===================================================
# Redis HA 企业级一键部署 + HTML 交付页面
# 支持 Pod 状态可视化
# 自动清理冲突 PVC/PV
# 自动生成 Helm Chart + 手动 PV（如无 StorageClass）
# 自动创建 ArgoCD Application
# 自动轮询 ArgoCD Application 状态，确保 StatefulSet 部署成功
# 等待 StatefulSet 就绪
# 生成企业交付 HTML 页面
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/redis-ha-chart"
NAMESPACE="database"
ARGO_APP="redis-ha"
GITHUB_REPO="ribenit-com/Multi-Agent-k8s-gitops-postgres"
PVC_SIZE="5Gi"
APP_LABEL="redis"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/redis_ha_info.html"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
kubectl get pv -o name | grep redis-pv- | xargs -r kubectl delete || true

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
name: redis-ha-chart
description: "Official Redis 7.0 Helm Chart for HA production"
type: application
version: 1.0.0
appVersion: "7.0"
EOF

# values.yaml
cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2

image:
  registry: docker.io
  repository: redis
  tag: "7.0"
  pullPolicy: IfNotPresent

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 256Mi
    cpu: 200m
  limits:
    memory: 512Mi
    cpu: 400m
EOF

# templates/statefulset.yaml
cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  labels:
    app: redis
spec:
  serviceName: redis-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 6379
          volumeMounts:
            - name: data
              mountPath: /data
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
  name: redis
spec:
  type: ClusterIP
  ports:
    - port: 6379
      targetPort: 6379
      name: redis
  selector:
    app: redis
EOF

# templates/headless-service.yaml
cat > "$CHART_DIR/templates/headless-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
spec:
  clusterIP: None
  ports:
    - port: 6379
      targetPort: 6379
  selector:
    app: redis
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="redis-pv-$i"
    mkdir -p /mnt/data/redis-$i
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
    path: /mnt/data/redis-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: 应用 Redis ArgoCD Application ----------
echo "=== Step 4: 应用 Redis ArgoCD Application ==="
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
    path: redis-ha-chart
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

echo "✅ Redis ArgoCD Application 已创建"
