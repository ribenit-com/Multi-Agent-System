#!/bin/bash
# ===================================================
# GitLab 内网生产环境 YAML 生成脚本（优化版）
# 功能：
#   - 根据参数生成 Namespace、Secret、StatefulSet、Service、PVC、CronJob YAML
#   - 支持动态 PVC（StorageClass）
#   - 支持优化资源、健康探针、Registry GC
# ===================================================

set -euo pipefail

# -----------------------------
# 配置参数（可通过命令行覆盖）
# -----------------------------
MODULE="${1:-GitLab_Prod}"                   # 模块名
WORK_DIR="${2:-$HOME/gitlab_scripts}"        # 输出目录
NAMESPACE="${3:-ns-gitlab}"                  # Namespace
STORAGE_CLASS="${4:-sc-ssd-high}"            # PVC StorageClass
PVC_SIZE="${5:-200Gi}"                        # PVC 容量
GITLAB_IMAGE="${6:-gitlab/gitlab-ce:latest}" # GitLab 镜像
DOMAIN="${7:-gitlab.local}"                  # GitLab 外部访问域名
NODE_IP="${8:-192.168.1.100}"               # 内网节点 IP
REGISTRY_PORT="${9:-35050}"                  # NodePort Registry
SSH_PORT="${10:-30022}"                       # NodePort SSH
HTTP_PORT="${11:-30080}"                      # NodePort HTTP

mkdir -p "$WORK_DIR"

# -----------------------------
# 生成 Namespace YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF

# -----------------------------
# 生成 Secret YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-secrets
  namespace: $NAMESPACE
stringData:
  root-password: "ReplaceWithStrongRandomPassword123!"
EOF

# -----------------------------
# 生成 StatefulSet + PVC YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_statefulset.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sts-gitlab
  namespace: $NAMESPACE
spec:
  serviceName: svc-gitlab
  replicas: 1
  selector:
    matchLabels:
      app: gitlab
  template:
    metadata:
      labels:
        app: gitlab
    spec:
      containers:
      - name: gitlab
        image: $GITLAB_IMAGE
        ports:
        - containerPort: 80
        - containerPort: 22
        - containerPort: 5050
        env:
        - name: GITLAB_OMNIBUS_CONFIG
          value: |
            external_url 'http://$DOMAIN'
            registry_external_url 'http://$NODE_IP:$REGISTRY_PORT'
            gitlab_rails['registry_enabled'] = true
            gitlab_rails['gitlab_cleanup_image_tags_enabled'] = true
            puma['worker_processes'] = 4
            postgresql['max_connections'] = 100
            nginx['listen_port'] = 80
            nginx['listen_https'] = false
        resources:
          requests:
            memory: "6Gi"
            cpu: "2000m"
          limits:
            memory: "12Gi"
        startupProbe:
          httpGet:
            path: /-/health
            port: 80
          failureThreshold: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /-/health
            port: 80
          initialDelaySeconds: 60
          periodSeconds: 20
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /-/readiness
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 15
        volumeMounts:
        - name: data
          mountPath: /var/opt/gitlab
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: $PVC_SIZE
      storageClassName: $STORAGE_CLASS
      volumeMode: Filesystem
EOF

# -----------------------------
# 生成 NodePort Service YAML
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: svc-gitlab-nodeport
  namespace: $NAMESPACE
spec:
  type: NodePort
  selector:
    app: gitlab
  ports:
  - name: http
    port: 80
    targetPort: 80
    nodePort: $HTTP_PORT
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: $SSH_PORT
  - name: registry
    port: 5050
    targetPort: 5050
    nodePort: $REGISTRY_PORT
EOF

# -----------------------------
# 生成 CronJob YAML（Registry GC）
# -----------------------------
cat <<EOF > "$WORK_DIR/${MODULE}_cronjob.yaml"
apiVersion: batch/v1
kind: CronJob
metadata:
  name: gitlab-gc-worker
  namespace: $NAMESPACE
spec:
  schedule: "0 3 * * 0" # 每周日凌晨3点
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: gc
            image: $GITLAB_IMAGE
            command: ["/bin/sh", "-c", "gitlab-ctl registry-garbage-collect -m"]
            volumeMounts:
            - name: data
              mountPath: /var/opt/gitlab
          restartPolicy: OnFailure
          volumes:
          - name: data
            persistentVolumeClaim:
              claimName: data
EOF

echo "✅ GitLab YAML 已生成到 $WORK_DIR"
echo "📦 Namespace: ${MODULE}_namespace.yaml"
echo "📦 Secret: ${MODULE}_secret.yaml"
echo "📦 StatefulSet + PVC: ${MODULE}_statefulset.yaml"
echo "📦 Service: ${MODULE}_service.yaml"
echo "📦 CronJob: ${MODULE}_cronjob.yaml"
