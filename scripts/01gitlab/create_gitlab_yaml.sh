#!/bin/bash
# ===================================================
# GitLab CE Kubernetes YAML 生成脚本（SC + PVC + 命名规则）
# 依据企业级 GitLab 命名规则手册
# 功能：
#   - 生成 StatefulSet、Service、PVC YAML
#   - 使用官方 GitLab CE 镜像
#   - 动态 PV，使用指定 StorageClass
# ===================================================

set -euo pipefail

# -----------------------------
# 配置参数
# -----------------------------
MODULE="${1:-GitLab_CE}"                # 模块名
WORK_DIR="${2:-$HOME/gitlab_helm_yaml}" # 输出目录
STORAGE_CLASS_NAME="${3:-sc-ssd-high}"  # SC 名称
PVC_SIZE="${4:-20Gi}"                   # PVC 容量
NAMESPACE="${5:-ns-app-gitlab-prod}"    # 命名规则：ns-<层级>-<环境>
APP_LABEL="${6:-gitlab}"                # app 标签
STATEFULSET_NAME="sts-gitlab-ce"        # sts-<组件名>
SERVICE_WEB="svc-gitlab-web"            # svc-<角色>
SERVICE_SSH="svc-gitlab-ssh"

mkdir -p "$WORK_DIR"

# -----------------------------
# 生成 PVC YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_pvc.yaml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-gitlab-data-0
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $STORAGE_CLASS_NAME
EOF

# -----------------------------
# 生成 StatefulSet YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_statefulset.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: $STATEFULSET_NAME
  namespace: $NAMESPACE
spec:
  serviceName: $SERVICE_WEB
  replicas: 1
  selector:
    matchLabels:
      app: $APP_LABEL
  template:
    metadata:
      labels:
        app: $APP_LABEL
    spec:
      containers:
      - name: gitlab
        image: gitlab/gitlab-ce:latest
        ports:
        - containerPort: 80    # HTTP
        - containerPort: 443   # HTTPS
        - containerPort: 22    # SSH
        env:
        - name: GITLAB_OMNIBUS_CONFIG
          value: |
            external_url 'http://gitlab.example.com'
        volumeMounts:
        - name: gitlab-data
          mountPath: /var/opt/gitlab
  volumeClaimTemplates:
  - metadata:
      name: gitlab-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: $PVC_SIZE
      storageClassName: $STORAGE_CLASS_NAME
EOF

# -----------------------------
# 生成 Service YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_WEB
  namespace: $NAMESPACE
spec:
  selector:
    app: $APP_LABEL
  ports:
    - port: 80
    - port: 443
---
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_SSH
  namespace: $NAMESPACE
spec:
  selector:
    app: $APP_LABEL
  ports:
    - port: 22
EOF

echo "✅ GitLab CE YAML 已生成到 $WORK_DIR"
echo "📦 PVC YAML: ${MODULE}_pvc.yaml"
echo "📦 StatefulSet YAML: ${MODULE}_statefulset.yaml"
echo "📦 Service YAML: ${MODULE}_service.yaml"
