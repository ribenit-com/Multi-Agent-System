#!/bin/bash
set -e

# -------------------- 1️⃣ 创建 Helm chart 目录 --------------------
CHART_DIR=postgres-chart

mkdir -p $CHART_DIR/templates

# -------------------- 2️⃣ Chart.yaml --------------------
cat > $CHART_DIR/Chart.yaml <<EOF
apiVersion: v2
name: postgres-chart
description: "Official PostgreSQL 16.3 Helm Chart for production"
type: application
version: 1.0.0
appVersion: "16.3"
EOF

# -------------------- 3️⃣ values.yaml --------------------
cat > $CHART_DIR/values.yaml <<EOF
replicaCount: 1

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
  existingClaim: postgres-pvc
  size: 10Gi
  storageClass: standard

resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 250m
    memory: 512Mi
EOF

# -------------------- 4️⃣ templates/deployment.yaml --------------------
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

# -------------------- 5️⃣ templates/service.yaml --------------------
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

# -------------------- 6️⃣ templates/pvc.yaml --------------------
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

# -------------------- 7️⃣ 创建 Namespace 和 ArgoCD Application --------------------
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
    repoURL: 'https://github.com/你的用户名/你的仓库.git'  # 替换为你自己的仓库
    targetRevision: main
    path: postgres-chart
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

echo "✅ Helm chart 生成完毕，Namespace 和 ArgoCD Application 已创建！"
echo "请 push 你的 Helm chart 到 Git 仓库，ArgoCD 会自动部署 PostgreSQL 官方镜像。"
