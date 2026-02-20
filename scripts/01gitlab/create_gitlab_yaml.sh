#!/bin/bash
# ===================================================
# GitLab 内网生产环境 YAML 生成脚本（企业级标准化命名）
# 功能：
#   - 自动生成 Namespace、Secret、StatefulSet、Service、PVC、CronJob YAML
#   - 增加日志打印，便于单元测试追溯问题
# ===================================================

set -euo pipefail

log() {
  echo "[$(date '+%F %T')] $*"
}

# -----------------------------
# 配置参数（可通过命令行覆盖）
# -----------------------------
MODULE="${1:-GitLab_Prod}"                   
WORK_DIR="${2:-$HOME/gitlab_scripts}"        
NAMESPACE="${3:-ns-app-gitlab-prod}"        
STORAGE_CLASS="${4:-sc-ssd-high}"            
PVC_SIZE="${5:-200Gi}"                        
GITLAB_IMAGE="${6:-gitlab/gitlab-ce:latest}" 
DOMAIN="${7:-gitlab.enterprise.local}"      
NODE_IP="${8:-192.168.1.100}"               
REGISTRY_PORT="${9:-35050}"                  
SSH_PORT="${10:-30022}"                       
HTTP_PORT="${11:-30080}"                       

log "🛠 模块: $MODULE"
log "📁 工作目录: $WORK_DIR"
log "🌐 Namespace: $NAMESPACE"
log "💾 PVC 大小: $PVC_SIZE, 存储类: $STORAGE_CLASS"
log "🐳 GitLab 镜像: $GITLAB_IMAGE"
log "🌍 域名: $DOMAIN, 节点IP: $NODE_IP"
log "🔌 端口: HTTP=$HTTP_PORT SSH=$SSH_PORT Registry=$REGISTRY_PORT"

mkdir -p "$WORK_DIR"
log "✅ 工作目录已创建或已存在"

# -----------------------------
# Namespace
# -----------------------------
NS_FILE="$WORK_DIR/${MODULE}_namespace.yaml"
cat <<EOF > "$NS_FILE"
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
EOF
log "📦 Namespace YAML 生成: $NS_FILE"

# -----------------------------
# Secret
# -----------------------------
SECRET_FILE="$WORK_DIR/${MODULE}_secret.yaml"
cat <<EOF > "$SECRET_FILE"
apiVersion: v1
kind: Secret
metadata:
  name: secret-app-gitlab
  namespace: $NAMESPACE
stringData:
  root-password: "ReplaceWithStrongRandomPassword123!"
EOF
log "📦 Secret YAML 生成: $SECRET_FILE"

# -----------------------------
# StatefulSet + PVC
# -----------------------------
STS_FILE="$WORK_DIR/${MODULE}_statefulset.yaml"
cat <<EOF > "$STS_FILE"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sts-app-gitlab
  namespace: $NAMESPACE
spec:
  serviceName: svc-app-gitlab
  replicas: 1
  selector:
    matchLabels:
      app: app-gitlab
  template:
    metadata:
      labels:
        app: app-gitlab
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
log "📦 StatefulSet + PVC YAML 生成: $STS_FILE"

# -----------------------------
# Service
# -----------------------------
SERVICE_FILE="$WORK_DIR/${MODULE}_service.yaml"
cat <<EOF > "$SERVICE_FILE"
apiVersion: v1
kind: Service
metadata:
  name: svc-app-gitlab
  namespace: $NAMESPACE
spec:
  type: NodePort
  selector:
    app: app-gitlab
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
log "📦 Service YAML 生成: $SERVICE_FILE"

# -----------------------------
# CronJob (Registry GC)
# -----------------------------
CRON_FILE="$WORK_DIR/${MODULE}_cronjob.yaml"
cat <<EOF > "$CRON_FILE"
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cron-app-gitlab-gc
  namespace: $NAMESPACE
spec:
  schedule: "0 3 * * 0"
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
log "📦 CronJob YAML 生成: $CRON_FILE"

# -----------------------------
# 完成提示
# -----------------------------
echo "✅ GitLab YAML 已生成到 $WORK_DIR"
echo "📦 Namespace: $(basename $NS_FILE)"
echo "📦 Secret: $(basename $SECRET_FILE)"
echo "📦 StatefulSet + PVC: $(basename $STS_FILE)"
echo "📦 Service: $(basename $SERVICE_FILE)"
echo "📦 CronJob: $(basename $CRON_FILE)"
log "🎉 YAML 生成完成"
