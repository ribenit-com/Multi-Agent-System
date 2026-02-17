#!/bin/bash
# ==============================================================================
# KubeEdge 集群全面健康检测脚本 (自动修复与增强版)
# ==============================================================================

# 1. 配置信息
export KUBECONFIG=/home/zdl/.kube/config
CONTROL_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAS_LOG_DIR="/mnt/truenas"
REPORT_FILE="${NAS_LOG_DIR}/kubeedge-report-${TIMESTAMP}.html"
LOG_FILE="${NAS_LOG_DIR}/kubeedge-check-${TIMESTAMP}.log"

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASSED=0; WARN=0; FAILED=0
SECTION_HTML=""

log() { echo -e "$1" | tee -a "$LOG_FILE"; }

# ------------------------------------------------------------------------------
# 2. 依赖工具自动检查与安装 (Netcat)
# ------------------------------------------------------------------------------
log "${BLUE}正在初始化检测环境...${NC}"

if ! command -v nc &> /dev/null; then
    log "${YELLOW}未发现 netcat，尝试自动安装...${NC}"
    if [ "$EUID" -ne 0 ]; then
        log "${RED}错误: 安装工具需要 root 权限，请使用 sudo ./script.sh 运行${NC}"
        exit 1
    fi
    apt-get update && apt-get install netcat-openbsd -y
    if [ $? -eq 0 ]; then
        log "${GREEN}✓ netcat 安装成功${NC}"
    else
        log "${RED}✗ netcat 安装失败，请手动检查网络或软件源${NC}"
        exit 1
    fi
else
    log "  ${GREEN}✓${NC} netcat 已就绪"
fi

# 检查 NAS 挂载状态
if [ ! -d "$NAS_LOG_DIR" ] || [ ! -w "$NAS_LOG_DIR" ]; then
    log "${RED}❌ 错误: NAS 路径 $NAS_LOG_DIR 未挂载或无写入权限${NC}"
    exit 1
fi

# ------------------------------------------------------------------------------
# 3. 核心检测项目
# ------------------------------------------------------------------------------
log "${BLUE}开始执行全面体检...${NC}"

# [3.1] 端口健康度
log "${YELLOW}[1/4] 核心端口检测...${NC}"
for PORT in 6443 10000 10002; do
    if nc -zv localhost $PORT &>/dev/null; then
        log "  ${GREEN}✓${NC} 端口 $PORT 正常"
        PASSED=$((PASSED+1))
        SECTION_HTML+="<tr><td>✅</td><td>端口 $PORT</td><td>可达</td><td>服务运行中</td></tr>"
    else
        log "  ${RED}✗${NC} 端口 $PORT 不可达"
        FAILED=$((FAILED+1))
        SECTION_HTML+="<tr><td>❌</td><td>端口 $PORT</td><td>失败</td><td>请检查相关 K8s/Edge 组件</td></tr>"
    fi
done

# [3.2] 硬件负载
log "${YELLOW}[2/4] 硬件负载检测...${NC}"
MEM_USAGE=$(free | awk '/^Mem:/{printf "%.1f", ($3/$2)*100}')
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
log "  内存: ${MEM_USAGE}% | 磁盘: ${DISK_USAGE}%"

if [ "$DISK_USAGE" -lt 85 ]; then
    PASSED=$((PASSED+1))
    SECTION_HTML+="<tr><td>✅</td><td>系统磁盘</td><td>${DISK_USAGE}%</td><td>空间充足</td></tr>"
else
    WARN=$((WARN+1))
    SECTION_HTML+="<tr><td>⚠️</td><td>系统磁盘</td><td>${DISK_USAGE}%</td><td>建议清理</td></tr>"
fi

# [3.3] K8s 节点与边缘机握手
log "${YELLOW}[3/4] K8s & 边缘节点状态...${NC}"
if kubectl get nodes &>/dev/null; then
    # 获取所有节点并循环处理
    while read -r line; do
        NODE_NAME=$(echo $line | awk '{print $1}')
        NODE_STATUS=$(echo $line | awk '{print $2}')
        NODE_ROLE=$(echo $line | awk '{print $3}')
        
        if [[ "$NODE_STATUS" == "Ready" ]]; then
            STATUS_ICON="✅"; PASSED=$((PASSED+1))
            log "  ${GREEN}✓${NC} 节点 $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
        else
            STATUS_ICON="❌"; FAILED=$((FAILED+1))
            log "  ${RED}✗${NC} 节点 $NODE_NAME ($NODE_ROLE): $NODE_STATUS"
        fi
        SECTION_HTML+="<tr><td>$STATUS_ICON</td><td>节点: $NODE_NAME</td><td>$NODE_STATUS</td><td>角色: $NODE_ROLE</td></tr>"
    done < <(kubectl get nodes --no-headers)
else
    log "  ${RED}❌ 无法获取 K8s 节点信息${NC}"
    FAILED=$((FAILED+1))
    SECTION_HTML+="<tr><td>❌</td><td>K8s 集群连接</td><td>失败</td><td>请检查 kubectl 配置</td></tr>"
fi

# ------------------------------------------------------------------------------
# 4. 生成 HTML 报告
# ------------------------------------------------------------------------------
TOTAL_CHECKS=$((PASSED+WARN+FAILED))
HEALTH_SCORE=$(( TOTAL_CHECKS>0 ? PASSED*100/TOTAL_CHECKS : 0 ))

cat > "$REPORT_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; background: #f0f2f5; }
        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #1a73e8; border-bottom: 2px solid #1a73e8; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
        th { background: #f8f9fa; font-weight: bold; }
        .score-box { font-size: 48px; font-weight: bold; color: #28a745; text-align: center; margin: 20px 0; }
        .info { color: #666; font-size: 0.9em; }
    </style>
    <title>KubeEdge 健康报告</title>
</head>
<body>
    <div class="card">
        <h1>🩺 KubeEdge 集群健康报告</h1>
        <p class="info">生成时间: $(date '+%Y-%m-%d %H:%M:%S') | 中央控制器: $CONTROL_IP</p>
        
        <div class="score-box">$HEALTH_SCORE%</div>
        <p style="text-align:center">通过: $PASSED | 警告: $WARN | 失败: $FAILED</p>

        <table>
            <tr><th>状态</th><th>检测项</th><th>详情</th><th>备注</th></tr>
            $SECTION_HTML
        </table>
    </div>
</body>
</html>
EOF

log ""
log "${GREEN}✅ 体检完成！${NC}"
log "  👉 HTML 报告: $REPORT_FILE"
log "  👉 详细日志: $LOG_FILE"
