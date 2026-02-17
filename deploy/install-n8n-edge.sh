cat > install-n8n-edge.sh << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
    local msg=$3
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${BLUE}[${NC}"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "${BLUE}]${NC} ${GREEN}%3d%%${NC} ${YELLOW}%s${NC}" "$percent" "$msg"
}

# 完成动画
show_done() {
    echo -e "\n${GREEN}✅ $1${NC}"
}

# 步骤计数
TOTAL_STEPS=8
CURRENT_STEP=0

clear
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    n8n 边缘机一键安装脚本 (Docker)    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# 步骤1: 检查 Docker
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "检查 Docker 环境..."
if ! command -v docker &> /dev/null; then
    echo -e "\n${RED}✗ Docker 未安装，开始安装 Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    newgrp docker
else
    show_done "Docker 已安装"
fi
sleep 1

# 步骤2: 检查 Docker 服务
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "检查 Docker 服务状态..."
if ! systemctl is-active --quiet docker; then
    echo -e "\n${YELLOW}启动 Docker 服务...${NC}"
    sudo systemctl start docker
    sudo systemctl enable docker
fi
show_done "Docker 服务运行正常"
sleep 1

# 步骤3: 创建存储目录
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "创建 n8n 数据目录..."
sudo mkdir -p /data/n8n
sudo chmod 777 /data/n8n
show_done "数据目录已创建: /data/n8n"
sleep 1

# 步骤4: 检查端口占用
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "检查端口 5678 占用..."
if ss -tuln | grep -q ":5678"; then
    echo -e "\n${YELLOW}端口 5678 被占用，尝试关闭占用进程...${NC}"
    sudo fuser -k 5678/tcp 2>/dev/null
    sleep 2
fi
show_done "端口 5678 可用"
sleep 1

# 步骤5: 拉取 n8n 镜像
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "拉取 n8n 镜像..."
docker pull n8nio/n8n:latest > /dev/null 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    show_progress $CURRENT_STEP $TOTAL_STEPS "拉取 n8n 镜像中..."
    sleep 1
done
show_done "n8n 镜像拉取完成"
sleep 1

# 步骤6: 停止并删除旧容器
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "清理旧容器..."
docker stop n8n 2>/dev/null
docker rm n8n 2>/dev/null
show_done "旧容器已清理"
sleep 1

# 步骤7: 启动 n8n 容器
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "启动 n8n 容器..."
docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -v /data/n8n:/home/node/.n8n \
  -e N8N_PORT=5678 \
  -e N8N_PROTOCOL=http \
  -e NODE_ENV=production \
  -e WEBHOOK_URL=http://192.168.1.20:5678 \
  -e N8N_HOST=192.168.1.20 \
  n8nio/n8n:latest > /dev/null

if [ $? -eq 0 ]; then
    show_done "n8n 容器启动成功"
else
    echo -e "\n${RED}✗ 容器启动失败${NC}"
    exit 1
fi
sleep 2

# 步骤8: 验证安装
CURRENT_STEP=$((CURRENT_STEP + 1))
show_progress $CURRENT_STEP $TOTAL_STEPS "验证 n8n 服务..."
sleep 3
if curl -s http://localhost:5678/healthz > /dev/null; then
    show_done "n8n 服务正常运行"
else
    echo -e "\n${YELLOW}⚠ 服务可能需要几秒钟完全启动，请稍后验证${NC}"
fi
sleep 1

# 完成
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}   n8n 安装成功！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "📦 容器信息："
echo -e "  ${BLUE}•${NC} 容器名称: ${GREEN}n8n${NC}"
echo -e "  ${BLUE}•${NC} 数据目录: ${GREEN}/data/n8n${NC}"
echo -e "  ${BLUE}•${NC} 访问端口: ${GREEN}5678${NC}"
echo ""
echo -e "🌐 访问地址："
echo -e "  ${BLUE}•${NC} 本地访问: ${GREEN}http://localhost:5678${NC}"
echo -e "  ${BLUE}•${NC} 远程访问: ${GREEN}http://192.168.1.20:5678${NC}"
echo ""
echo -e "📝 常用命令："
echo -e "  ${BLUE}•${NC} 查看日志: ${YELLOW}docker logs -f n8n${NC}"
echo -e "  ${BLUE}•${NC} 停止服务: ${YELLOW}docker stop n8n${NC}"
echo -e "  ${BLUE}•${NC} 启动服务: ${YELLOW}docker start n8n${NC}"
echo -e "  ${BLUE}•${NC} 重启服务: ${YELLOW}docker restart n8n${NC}"
echo ""

# 显示实时日志
echo -e "${YELLOW}是否查看实时日志？(y/n)${NC}"
read -p "请输入: " VIEW_LOGS
if [ "$VIEW_LOGS" = "y" ] || [ "$VIEW_LOGS" = "Y" ]; then
    echo -e "${BLUE}显示最近50行日志（按 Ctrl+C 退出）...${NC}"
    sleep 2
    docker logs --tail 50 n8n
    echo -e "\n${YELLOW}跟踪实时日志？(y/n)${NC}"
    read -p "请输入: " FOLLOW_LOGS
    if [ "$FOLLOW_LOGS" = "y" ] || [ "$FOLLOW_LOGS" = "Y" ]; then
        docker logs -f n8n
    fi
fi

echo -e "${GREEN}安装脚本执行完毕！${NC}"
EOF

# 添加执行权限
chmod +x install-n8n-edge.sh

echo -e "${GREEN}安装脚本已创建！${NC}"
echo -e "现在运行：${YELLOW}./install-n8n-edge.sh${NC}"
