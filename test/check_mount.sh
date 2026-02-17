#!/bin/bash
# ============================================
# 简单检测并生成体检报告
# ============================================

NAS_PATH="/mnt/truenas"
# 我们把文件名定死，方便你去查看
REPORT_FILE="$NAS_PATH/cluster_health_report.md"

echo "--- 开始检测 ---"

# 1. 检查目录
if [ -d "$NAS_PATH" ]; then
    echo "✅ 路径存在"
else
    echo "❌ 路径不存在，请检查挂载命令"
    exit 1
fi

# 2. 写入真正的体检报告（不删除，留给你看）
{
    echo "# 🩺 K8s 节点健康体检"
    echo "检测时间: $(date)"
    echo "---"
    echo "### 1. 存储状态"
    echo "- 挂载路径: $NAS_PATH"
    echo "- 剩余空间: $(df -h $NAS_PATH | awk 'NR==2 {print $4}')"
    echo -e "\n### 2. K8s 节点状态"
    kubectl get nodes
} > "$REPORT_FILE" 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 报告生成成功！"
    echo "📂 请去 TrueNAS 对应的文件夹查看: cluster_health_report.md"
else
    echo "❌ 写入失败，请检查 TrueNAS 的 NFS 权限设置"
fi
