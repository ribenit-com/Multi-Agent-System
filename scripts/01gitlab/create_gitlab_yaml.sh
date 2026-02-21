#!/bin/bash
set -euo pipefail

#########################################
# 参数
#########################################
MODULE="${1:-}"
YAML_DIR="${2:-/mnt/truenas/Gitlab_yaml_output}"
OUTPUT_DIR="${3:-/mnt/truenas/Gitlab_output}"

if [[ -z "$MODULE" ]]; then
    echo "❌ 用法: $0 <MODULE> [YAML_DIR] [OUTPUT_DIR]"
    exit 1
fi

mkdir -p "$YAML_DIR"
mkdir -p "$OUTPUT_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#########################################
# 模块标准化
#########################################
MODULE_LOWER=$(echo "$MODULE" | tr '[:upper:]' '[:lower:]')
MODULE_CLEAN=$(echo "$MODULE_LOWER" | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')

#########################################
# 统一命名规范
#########################################
NAMESPACE="ns-${MODULE_CLEAN}-ha"
STATEFULSET_NAME="sts-${MODULE_CLEAN}-ha"
SERVICE_PRIMARY="svc-${MODULE_CLEAN}-primary"
SERVICE_REPLICA="svc-${MODULE_CLEAN}-replica"
SECRET_NAME="secret-${MODULE_CLEAN}-password"
CONFIGMAP_NAME="cm-${MODULE_CLEAN}-config"
NETWORK_POLICY="np-${MODULE_CLEAN}-ha"

log "📌 统一命名:"
log "   Namespace      : $NAMESPACE"
log "   StatefulSet    : $STATEFULSET_NAME"
log "   ServicePrimary : $SERVICE_PRIMARY"
log "   ServiceReplica : $SERVICE_REPLICA"
log "   Secret         : $SECRET_NAME"
log "   ConfigMap      : $CONFIGMAP_NAME"
log "   NetworkPolicy  : $NETWORK_POLICY"

#########################################
# Namespace
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

#########################################
# Secret
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  password: change_me
EOF

#########################################
# ConfigMap
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIGMAP_NAME}
  namespace: ${NAMESPACE}
data:
  example.conf: |
    external_url 'http://gitlab.local'
EOF

#########################################
# StatefulSet
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${STATEFULSET_NAME}
  namespace: ${NAMESPACE}
spec:
  serviceName: "${SERVICE_PRIMARY}"
  replicas: 1
  selector:
    matchLabels:
      app: ${STATEFULSET_NAME}
  template:
    metadata:
      labels:
        app: ${STATEFULSET_NAME}
    spec:
      containers:
      - name: gitlab
        image: gitlab/gitlab-ce:latest
        ports:
        - containerPort: 80
EOF

#########################################
# Service Primary
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_service_primary.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_PRIMARY}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${STATEFULSET_NAME}
  ports:
  - port: 80
    targetPort: 80
EOF

#########################################
# Service Replica
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_service_replica.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_REPLICA}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${STATEFULSET_NAME}
  ports:
  - port: 80
    targetPort: 80
EOF

#########################################
# NetworkPolicy
#########################################
cat > "$YAML_DIR/${MODULE_CLEAN}_networkpolicy.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${NETWORK_POLICY}
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

#########################################
# JSON 输出
#########################################
JSON_FILE="$OUTPUT_DIR/${MODULE_CLEAN}_info.json"

cat > "$JSON_FILE" <<EOF
{
  "module": "${MODULE_CLEAN}",
  "namespace": "${NAMESPACE}",
  "statefulset": "${STATEFULSET_NAME}",
  "service_primary": "${SERVICE_PRIMARY}",
  "service_replica": "${SERVICE_REPLICA}",
  "secret": "${SECRET_NAME}",
  "configmap": "${CONFIGMAP_NAME}",
  "networkpolicy": "${NETWORK_POLICY}",
  "generated_at": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

#########################################
# HTML 报告
#########################################
HTML_FILE="$OUTPUT_DIR/${MODULE_CLEAN}_info.html"

cat > "$HTML_FILE" <<EOF
<html>
<head><title>GitLab Deployment Report</title></head>
<body>
<h1>GitLab Deployment Report</h1>
<ul>
<li>Namespace: ${NAMESPACE}</li>
<li>StatefulSet: ${STATEFULSET_NAME}</li>
<li>Service Primary: ${SERVICE_PRIMARY}</li>
<li>Service Replica: ${SERVICE_REPLICA}</li>
<li>Secret: ${SECRET_NAME}</li>
<li>ConfigMap: ${CONFIGMAP_NAME}</li>
<li>NetworkPolicy: ${NETWORK_POLICY}</li>
</ul>
<p>Generated At: $(date)</p>
</body>
</html>
EOF

log "✅ 统一规范 YAML / JSON / HTML 已生成"
log "📄 HTML 报告路径: $HTML_FILE"
