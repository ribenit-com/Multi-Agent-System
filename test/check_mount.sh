#!/bin/bash

# 1. 自动定位 K8s 配置文件 (防止 sudo 运行时找不到命令)
export KUBECONFIG=/home/zdl/.kube/config

NAS_PATH="/mnt/truenas"
REPORT_FILE="$NAS_PATH/cluster_health_report.md"

echo "--- 开始深度检测 ---"

# 2. 确保目录存在
if [ ! -d "$NAS_PATH" ]; then
    echo "❌ 错误: $NAS_PATH 未挂载或目录不存在"
    exit 1
fi

# 3. 使用临时文件中转，最后再一次性写入（避开权限碎碎念）
TEMP_LOG="/tmp/health_tmp.md"

{
    echo "# 🩺 K8s 节点健康体检"
    echo "检测时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "---"
    echo "### 1. 存储状态"
    echo "- 挂载路径: $NAS_PATH"
    echo "- 硬盘余量: $(df -h $NAS_PATH | awk 'NR==2 {print $4}')"
    
    echo -e "\n### 2. K8s 节点状态"
    echo '```'
    kubectl get nodes 2>&1
    echo '```'
    
    echo -e "\n### 3. 边缘节点 (KubeEdge) 详细状态"
    echo '```'
    kubectl get nodes -l node-role.kubernetes.io/edge -o wide 2>&1
    echo '```'
} > "$TEMP_LOG"

# 4. 强力写入 NAS
sudo cp "$TEMP_LOG" "$REPORT_FILE" && sudo chmod 666 "$REPORT_FILE"

if [ $? -eq 0 ]; then
    echo "✅ 报告已成功推送到 TrueNAS！"
    echo "📂 文件名: $REPORT_FILE"
else
    echo "❌ 写入 NAS 失败"
fi
