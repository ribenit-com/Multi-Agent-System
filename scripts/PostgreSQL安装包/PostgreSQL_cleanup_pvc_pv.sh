#!/bin/bash
# ===================================================
# 脚本名称: generate_postgresql_report_dir.sh
# 功能: 生成 PostgreSQL HA 企业交付报告
#       - 输出到 /mnt/truenas/PostgreSQL安装报告书/
#       - 文件名: PostgreSQL安装报告书-命名规约检测报告书.html
# ===================================================

# ------------------------------
# 配置
# ------------------------------
NAMESPACE=${NAMESPACE:-ns-mid-storage}
APP_LABEL=${APP_LABEL:-postgres}
BASE_DIR="/mnt/truenas"
REPORT_DIR="$BASE_DIR/PostgreSQL安装报告书"
HTML_FILE="$REPORT_DIR/PostgreSQL安装报告书-命名规约检测报告书.html"

# 创建报告目录
mkdir -p "$REPORT_DIR"

# ------------------------------
# 获取 PostgreSQL 资源信息
# ------------------------------
STS_LIST=$(kubectl -n $NAMESPACE get sts -l app=$APP_LABEL -o name || echo "未发现 StatefulSet")
SERVICE_LIST=$(kubectl -n $NAMESPACE get svc -l app=$APP_LABEL -o name || echo "未发现 Service")
PVC_LIST=$(kubectl -n $NAMESPACE get pvc -l app=$APP_LABEL -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
POD_STATUS=$(kubectl -n $NAMESPACE get pods -l app=$APP_LABEL -o custom-columns=NAME:.metadata.name,STATUS:.status.phase --no-headers || true)

PRIMARY_SVC=$(echo "$SERVICE_LIST" | head -n1 | awk -F'/' '{print $2}')
SERVICE_IP=$(kubectl -n $NAMESPACE get svc $PRIMARY_SVC -o jsonpath='{.spec.clusterIP}' || echo "127.0.0.1")
REPLICA_COUNT=$(kubectl -n $NAMESPACE get sts -l app=$APP_LABEL -o jsonpath='{.items[0].spec.replicas}' || echo "2")

# ------------------------------
# 生成 HTML
# ------------------------------
cat > "$HTML_FILE" <<EOF
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>PostgreSQL 安装报告书 - 命名规约检测报告书</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body {margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f7fa}
.container {display:flex;justify-content:center;align-items:flex-start;padding:30px}
.card {background:#fff;padding:30px 40px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.08);width:750px}
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
<h2>🎉 PostgreSQL HA 安装报告书 - 命名规约检测</h2>

<h3>基本信息</h3>
<div class="info"><span class="label">Namespace:</span><span class="value">$NAMESPACE</span></div>
<div class="info"><span class="label">主服务:</span><span class="value">$PRIMARY_SVC</span></div>
<div class="info"><span class="label">ClusterIP:</span><span class="value">$SERVICE_IP</span></div>
<div class="info"><span class="label">端口:</span><span class="value">5432</span></div>
<div class="info"><span class="label">副本数:</span><span class="value">$REPLICA_COUNT</span></div>

<h3>StatefulSet 列表</h3>
<pre>$STS_LIST</pre>

<h3>Service 列表</h3>
<pre>$SERVICE_LIST</pre>

<h3>PVC 列表</h3>
<pre>$PVC_LIST</pre>

<h3>Pod 状态</h3>
<pre>
EOF

# Pod 状态逐行输出
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
kubectl -n $NAMESPACE port-forward svc/$PRIMARY_SVC 5432:5432
psql -h localhost -U postgres -d postgres
</pre>

<h3>Python 示例</h3>
<pre>
import psycopg2
conn = psycopg2.connect(host="$SERVICE_IP", port=5432, user="postgres", password="yourpassword", dbname="postgres")
cur = conn.cursor()
cur.execute("SELECT version();")
print(cur.fetchone())
conn.close()
</pre>

<h3>Java 示例</h3>
<pre>
String url = "jdbc:postgresql://$SERVICE_IP:5432/postgres";
Connection conn = DriverManager.getConnection(url, "postgres", "yourpassword");
Statement stmt = conn.createStatement();
ResultSet rs = stmt.executeQuery("SELECT version();");
while(rs.next()) System.out.println(rs.getString(1));
conn.close();
</pre>

<div class="footer">
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
</div>

</div>
</div>
</body>
</html>
EOF

echo "✅ PostgreSQL 安装报告书生成完成: $HTML_FILE"
