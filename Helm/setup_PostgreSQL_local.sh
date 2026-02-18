#!/bin/bash
set -e

# -------------------- 配置区 --------------------
CHART_DIR="postgres-chart"

POSTGRES_USER="myuser"
POSTGRES_PASSWORD="mypassword"
POSTGRES_DB="mydb"
PVC_NAME="postgres-pvc"
STORAGE_CLASS="standard"
STORAGE_SIZE="10Gi"
IMAGE_REGISTRY="docker.m.daocloud.io"
IMAGE_REPO="library/postgres"
IMAGE_TAG="16.3"

# -------------------- 1️⃣ 创建 Helm chart --------------------
mkdir -p $CHART_DIR/templates

cat > $CHART_DIR/Chart.yaml <<EOF
apiVersion: v2
name: postgres-chart
description: "Official PostgreSQL 16.3 Helm Chart for production"
type: application
version: 1.0.0
appVersion: "16.3"
EOF

cat > $CHART_DIR/values.yaml <<EOF
replicaCount: 1

image:
  registry: $IMAGE_REGISTRY
  repository: $IMAGE_REPO
  tag: "$IMAGE_TAG"
  pullPolicy: IfNotPresent

postgresql:
  username: $POSTGRES_USER
  password: $POSTGRES_PASSWORD
  database: $POSTGRES_DB

persistence:
  enabled: true
  existingClaim: $PVC_NAME
  size: $STORAGE_SIZE
  storageClass: $STORAGE_CLASS

resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 512Mi
EOF

cat > $CHART_DIR/templates/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "postgres-chart.fullname" . }}
  labels:
    app: {{ include "postgres-chart.name" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "postgres-chart.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "postgres-chart.name" . }}
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
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ .Values.persistence.existingClaim }}
EOF

cat > $CHART_DIR/templates/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: {{ include "postgres-chart.fullname" . }}
spec:
  type: ClusterIP
  ports:
    - port: 5432
      targetPort: 5432
      protocol: TCP
      name: postgres
  selector:
    app: {{ include "postgres-chart.name" . }}
EOF

cat > $CHART_DIR/templates/pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.persistence.existingClaim }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
  storageClassName: {{ .Values.persistence.storageClass }}
EOF

# -------------------- 2️⃣ 创建 Namespace 和 ArgoCD Application --------------------
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: database
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgres-official
  namespace: argocd
spec:
  project: default
  source:
    path: $CHART_DIR
    repoURL: 'https://github.com/your-git-repo.git'  # 这里你上传后填自己仓库
    targetRevision: main
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: database
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "✅ PostgreSQL Helm chart 已生成，Namespace 和 ArgoCD Application 已创建！"
