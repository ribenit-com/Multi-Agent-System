#!/bin/bash
set -Eeuo pipefail

# ===================================================
# n8n HA 企业级一键部署 + HTML 交付页面
# 支持 containerd 节点、Pod 状态可视化
# ===================================================

# ---------- 配置 ----------
CHART_DIR="$HOME/gitops/n8n-ha-chart"
NAMESPACE="automation"
ARGO_APP="n8n-ha"
PVC_SIZE="10Gi"
APP_LABEL="n8n"
LOG_DIR="/mnt/truenas"
HTML_FILE="${LOG_DIR}/n8n_ha_info.html"
N8N_IMAGE="n8nio/n8n:2.8.2"

mkdir -p "$CHART_DIR/templates" "$LOG_DIR"

# ---------- Step 0: 清理已有 PVC/PV ----------
echo "=== Step 0: 清理已有 PVC/PV ==="
kubectl delete pvc -n $NAMESPACE -l app=$APP_LABEL --ignore-not-found --wait=false || true
kubectl get pv -o name | grep n8n-pv- | xargs -r kubectl delete --ignore-not-found --wait=false || true

# ---------- Step 0.5: 检查 containerd 镜像（离线/本地镜像） ----------
echo "=== Step 0.5: 检查 containerd 镜像 ==="
if ! sudo ctr -n k8s.io images ls | grep -q "${N8N_IMAGE}"; then
  echo "⚠️ containerd 上没有 $N8N_IMAGE 镜像，请确保已手动导入离线镜像"
  echo "导入命令示例: sudo ctr -n k8s.io image import n8n_2.8.2.tar"
  exit 1
else
  echo "✅ containerd 上已存在镜像: $N8N_IMAGE"
fi

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
cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: n8n-ha-chart
description: "n8n HA Helm Chart"
type: application
version: 1.0.0
appVersion: "2.8.2"
EOF

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 2
image:
  registry: n8nio
  repository: n8n
  tag: "2.8.2"
  pullPolicy: Never  # 使用本地 containerd 镜像

persistence:
  enabled: true
  size: $PVC_SIZE
  storageClass: ${SC_NAME:-""}

resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 250m
EOF

cat > "$CHART_DIR/templates/statefulset.yaml" <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: n8n
  labels:
    app: n8n
spec:
  serviceName: n8n-headless
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      containers:
        - name: n8n
          image: "{{ .Values.image.registry }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 5678
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

cat > "$CHART_DIR/templates/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: n8n
spec:
  type: ClusterIP
  ports:
    - port: 5678
      targetPort: 5678
      name: http
  selector:
    app: n8n
EOF

cat > "$CHART_DIR/templates/headless-service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: n8n-headless
spec:
  clusterIP: None
  ports:
    - port: 5678
      targetPort: 5678
  selector:
    app: n8n
EOF

# ---------- Step 3: 手动 PV (如无 StorageClass) ----------
if [ -z "$SC_NAME" ]; then
  echo "=== Step 3: 创建手动 PV ==="
  for i in $(seq 0 1); do
    PV_NAME="n8n-pv-$i"
    mkdir -p /mnt/data/n8n-$i
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
    path: /mnt/data/n8n-$i
  persistentVolumeReclaimPolicy: Retain
EOF
    kubectl apply -f /tmp/$PV_NAME.yaml
  done
fi

# ---------- Step 4: 使用 Helm 安装 n8n HA ----------
echo "=== Step 4: 使用 Helm 安装 n8n HA ==="
if helm status n8n-ha -n $NAMESPACE >/dev/null 2>&1; then
  echo "Release 已存在，升级 Helm Chart..."
  helm upgrade n8n-ha "$CHART_DIR" -n $NAMESPACE
else
  echo "Release 不存在，安装 Helm Chart..."
  helm install n8n-ha "$CHART_DIR" -n $NAMESPACE --create-namespace
fi

# ---------- Step 4a: 等待 StatefulSet ----------
echo "等待 n8n StatefulSet 就绪..."
for i in {1..60}; do
  if kubectl -n $NAMESPACE get sts n8n >/dev/null 2>&1; then
    READY=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.status.readyReplicas}' || echo "0")
    DESIRED=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' || echo "2")
    echo "[${i}] StatefulSet n8n: $READY/$DESIRED 就绪"
    if [ "$READY" == "$DESIRED" ]; then
      echo "✅ StatefulSet 已就绪"
      break
    fi
  else
    echo "[${i}] StatefulSet n8n 尚未创建，等待 5s..."
  fi
  sleep 5
done

# ---------- Step 5: 生成企业交付 HTML ----------
echo "=== Step 5: 生成 HTML 页面 ==="
SERVICE_IP=$(kubectl -n $NAMESPACE get svc n8n -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts n8n -o jsonpath='{.spec.replicas}' || echo "2")

POD_STATUS=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers || true)

cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>n8n HA 企业交付指南</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:650px}
h2 {color:#1677ff;margin-bottom:20px;text-align:center}
h3 {color:#444;margin-top:25px;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px}
pre {background:#f0f2f5;padding:12px;border-radius:6px;overflow-x:auto;font-family:monospace}
.info {margin-bottom:10px}
.label {font-weight:600;color:#333}
.value {color:#555;margin-left:5px}
.status-running {color:green;font-weight:600}
.status-pending {color:orange;font-weight:600}
.status-failed {color:red;font-weight:600}
.footer {margin-top:20px;font-size:12px;color:#888;text-align:center}
</style>
</head>
<body>
<div class="container">
<div class="card">
<h2>🎉 n8n HA 安装完成</h2>

<h3>数据库信息</h3>
<div class="info"><span class="label">Namespace:</span><span class="value">$NAMESPACE</span></div>
<div class="info"><span class="label">Service:</span><span class="value">n8n</span></div>
<div class="info"><span class="label">ClusterIP:</span><span class="value">$SERVICE_IP</span></div>
<div class="info"><span class="label">端口:</span><span class="value">5678</span></div>
<div class="info"><span class="label">副本数:</span><span class="value">$REPLICA_COUNT</span></div>

<h3>PVC 列表</h3>
<pre>$PVC_LIST</pre>

<h3>Pod 状态</h3>
<pre>
EOF

while read -r line; do
  POD_NAME=$(echo $line | awk '{print $1}')
  STATUS=$(echo $line | awk '{print $2}')
  CASE_CLASS="status-failed"
  [[ "$STATUS" == "Running" ]] && CASE_CLASS="status-running"
  [[ "$STATUS" == "Pending" ]] && CASE_CLASS="status-pending"
  echo "<div class=\"$CASE_CLASS\">$POD_NAME : $STATUS</div>" >> "$HTML_FILE"
done <<< "$POD_STATUS"

cat >> "$HTML_FILE" <<EOF
</pre>

<h3>访问方式</h3>
<pre>
kubectl -n $NAMESPACE port-forward svc/n8n 5678:5678
</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</div>
</body>
</html>
EOF

echo "✅ n8n HA 企业交付 HTML 页面已生成: $HTML_FILE"
