cat > install-n8n-edge-fixed.sh << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    n8n 边缘机一键安装脚本 (修复版)    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# 步骤1: 检查 Docker
echo -e "${YELLOW}[1/7] 检查 Docker 环境...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker 未安装，开始安装 Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    echo -e "${GREEN}✓ Docker 安装完成${NC}"
    echo -e "${YELLOW}请手动执行以下命令完成安装：${NC}"
    echo -e "  ${BLUE}1.${NC} sudo usermod -aG docker \$USER"
    echo -e "  ${BLUE}2.${NC} newgrp docker  # 或者退出重新登录"
    echo -e "  ${BLUE}3.${NC} 重新运行此脚本的后半部分"
    exit 0
else
    echo -e "${GREEN}✓ Docker 已安装${NC}"
fi

# 步骤2: 检查 Docker 服务
echo -e "${YELLOW}[2/7] 检查 Docker 服务状态...${NC}"
if ! systemctl is-active --quiet docker; then
    sudo systemctl start docker
    sudo systemctl enable docker
fi
echo -e "${GREEN}✓ Docker 服务运行正常${NC}"

# 步骤3: 创建存储目录
echo -e "${YELLOW}[3/7] 创建 n8n 数据目录...${NC}"
sudo mkdir -p /data/n8n
sudo chmod 777 /data/n8n
echo -e "${GREEN}✓ 数据目录已创建: /data/n8n${NC}"

# 步骤4: 检查端口
echo -e "${YELLOW}[4/7] 检查端口 5678 占用...${NC}"
if ss -tuln | grep -q ":5678"; then
    echo -e "${YELLOW}端口 5678 被占用，尝试关闭占用进程...${NC}"
    sudo fuser -k 5678/tcp 2>/dev/null
    sleep 2
fi
echo -e "${GREEN}✓ 端口 5678 可用${NC}"

# 步骤5: 拉取镜像
echo -e "${YELLOW}[5/7] 拉取 n8n 镜像...${NC}"
docker pull n8nio/n8n:latest
echo -e "${GREEN}✓ 镜像拉取完成${NC}"

# 步骤6: 清理旧容器
echo -e "${YELLOW}[6/7] 清理旧容器...${NC}"
docker stop n8n 2>/dev/null
docker rm n8n 2>/dev/null
echo -e "${GREEN}✓ 旧容器已清理${NC}"

# 步骤7: 启动容器
echo -e "${YELLOW}[7/7] 启动 n8n 容器...${NC}"
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
  n8nio/n8n:latest

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ n8n 容器启动成功${NC}"
else
    echo -e "${RED}✗ 容器启动失败${NC}"
    exit 1
fi

# 验证
sleep 3
if curl -s http://localhost:5678/healthz > /dev/null; then
    echo -e "${GREEN}✓ n8n 服务正常运行${NC}"
else
    echo -e "${YELLOW}⚠ 服务可能需要几秒钟完全启动${NC}"
fi

# 完成
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}   n8n 安装成功！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "访问地址: ${GREEN}http://192.168.1.20:5678${NC}"
echo -e "本地访问: ${GREEN}http://localhost:5678${NC}"
echo ""
echo -e "查看日志: ${YELLOW}docker logs -f n8n${NC}"
EOF

chmod +x install-n8n-edge-fixed.sh
