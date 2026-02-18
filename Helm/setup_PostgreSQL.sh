#!/bin/bash
set -e

# -------------------- 配置区 --------------------
GIT_REPO="git@github.com:你的用户名/Multi-Agent-k8s-gitops-postgres.git"
GIT_BRANCH="main"
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

# -------------------- 2️⃣ 初始化或清理 Git 仓库 --------------------
if [ -d ".git" ]; then
  echo "⚡ 已存在 Git 仓库，清理 main 分支"
  git checkout --orphan temp-clean
  git add .
  git commit -m "Clean main commit"
  git branch -D $GIT_BRANCH
  git branch -m $GIT_BRANCH
else
  echo "⚡ 初始化 Git 仓库"
  git init
  git checkout -b $GIT_BRANCH
  git add $CHART_DIR
  git commit -m "Add PostgreSQL Helm chart"
fi

# 关联远程并强制 push
git remote remove origin 2>/dev/null || true
git remote add origin $GIT_REPO
git push -f origin $GIT_BRANCH

# -------------------- 3️⃣ 创建 Namespace 和 ArgoCD Application --------------------
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
    repoURL: '$GIT_REPO'
    targetRevision: $GIT_BRANCH
    path: $CHART_DIR
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

# -------------------- 4️⃣ 刷新 ArgoCD 缓存 --------------------
argocd app sync postgres-official --refresh || true

echo "✅ PostgreSQL Helm chart 已生成、Git 已推送，Namespace 和 ArgoCD Application 已创建并刷新缓存！"
