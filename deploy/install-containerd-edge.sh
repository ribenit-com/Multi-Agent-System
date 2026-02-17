cat > install-containerd-edge.sh << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    边缘节点 Containerd 一键安装脚本    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# 步骤1: 检查系统
echo -e "${YELLOW}[1/7] 检查系统环境...${NC}"
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}✗ 无法识别操作系统${NC}"
    exit 1
fi
. /etc/os-release
echo -e "${GREEN}✓ 系统: $NAME $VERSION${NC}"
sleep 1

# 步骤2: 检查是否已安装 containerd
echo -e "${YELLOW}[2/7] 检查 containerd 环境...${NC}"
if command -v containerd &> /dev/null; then
    echo -e "${GREEN}✓ containerd 已安装${NC}"
    containerd --version
else
    echo -e "${RED}✗ containerd 未安装，开始安装...${NC}"
fi
sleep 1

# 步骤3: 安装 containerd
echo -e "${YELLOW}[3/7] 安装 containerd...${NC}"

# 更新 apt 源
sudo apt-get update

# 安装依赖
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 添加 Docker 官方 GPG 密钥和仓库（containerd 从这里安装）
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新并安装 containerd
sudo apt-get update
sudo apt-get install -y containerd.io

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ containerd 安装完成${NC}"
else
    echo -e "${RED}✗ containerd 安装失败${NC}"
    exit 1
fi
sleep 1

# 步骤4: 配置 containerd
echo -e "${YELLOW}[4/7] 配置 containerd...${NC}"

# 生成默认配置
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# 重要：配置 SystemdCgroup 驱动（生产环境必须）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# 确保 cri 插件启用（检查并修改 disabled_plugins）
sudo sed -i 's/disabled_plugins = \["cri"\]/disabled_plugins = \[\]/g' /etc/containerd/config.toml

echo -e "${GREEN}✓ containerd 配置完成${NC}"
sleep 1

# 步骤5: 启动 containerd 服务
echo -e "${YELLOW}[5/7] 启动 containerd 服务...${NC}"

# 重新加载 systemd 配置
sudo systemctl daemon-reload

# 启动并启用 containerd
sudo systemctl start containerd
sudo systemctl enable containerd

# 检查服务状态
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}✓ containerd 服务启动成功${NC}"
else
    echo -e "${RED}✗ containerd 服务启动失败${NC}"
    sudo systemctl status containerd --no-pager
    exit 1
fi
sleep 1

# 步骤6: 验证安装
echo -e "${YELLOW}[6/7] 验证 containerd 安装...${NC}"

# 使用 ctr 命令验证
if sudo ctr version &> /dev/null; then
    echo -e "${GREEN}✓ ctr 命令可用${NC}"
    sudo ctr version | head -3
else
    echo -e "${RED}✗ ctr 命令验证失败${NC}"
fi

# 使用 crictl 验证（如果安装了）
if command -v crictl &> /dev/null; then
    sudo crictl version
else
    echo -e "${YELLOW}⚠ crictl 未安装，跳过${NC}"
fi
sleep 1

# 步骤7: 安装 crictl（用于调试）
echo -e "${YELLOW}[7/7] 安装 crictl 调试工具...${NC}"

# 获取最新版本
CRICTL_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/cri-tools/releases/latest | grep tag_name | cut -d '"' -f 4 | cut -c 2-)

if [ -n "$CRICTL_VERSION" ]; then
    wget -q https://github.com/kubernetes-sigs/cri-tools/releases/download/v$CRICTL_VERSION/crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
    sudo tar zxvf crictl-v$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
    rm -f crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
    
    # 配置 crictl
    sudo tee /etc/crictl.yaml << 'CRICTL'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
CRICTL
    
    echo -e "${GREEN}✓ crictl 安装完成${NC}"
    crictl version
else
    echo -e "${YELLOW}⚠ crictl 安装失败，可手动安装${NC}"
fi

# 完成
echo -e "\n${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}   Containerd 安装成功！${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo -e "📦 版本信息："
echo -e "  ${BLUE}•${NC} containerd: $(containerd --version | awk '{print $3}')"
echo -e "  ${BLUE}•${NC} 服务状态: $(systemctl is-active containerd)"
echo ""
echo -e "🔧 常用命令："
echo -e "  ${BLUE}•${NC} 查看版本: ${YELLOW}containerd --version${NC}"
echo -e "  ${BLUE}•${NC} 查看状态: ${YELLOW}sudo systemctl status containerd${NC}"
echo -e "  ${BLUE}•${NC} 查看日志: ${YELLOW}sudo journalctl -u containerd -f${NC}"
echo -e "  ${BLUE}•${NC} 使用 ctr: ${YELLOW}sudo ctr namespace ls${NC}"
echo -e "  ${BLUE}•${NC} 使用 crictl: ${YELLOW}sudo crictl images${NC}"
echo ""
echo -e "📝 配置文件："
echo -e "  ${BLUE}•${NC} 主配置: ${YELLOW}/etc/containerd/config.toml${NC}"
echo -e "  ${BLUE}•${NC} SystemdCgroup: ${GREEN}已启用${NC}"
echo -e "  ${BLUE}•${NC} CRI 插件: ${GREEN}已启用${NC}"
echo ""
echo -e "${GREEN}✅ containerd 安装完成，可以继续部署 n8n！${NC}"
EOF

chmod +x install-containerd-edge.sh

echo -e "${GREEN}Containerd 安装脚本已创建！${NC}"
echo -e "在边缘机（.20）运行：${YELLOW}./install-containerd-edge.sh${NC}"
