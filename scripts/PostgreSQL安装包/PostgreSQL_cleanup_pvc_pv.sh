#!/bin/bash
# ===================================================
# 脚本名称: 01_cleanup_pvc_pv.sh
# 功能: 清理 PostgreSQL HA 部署过程中可能存在的旧 PVC/PV
# 用途: 避免 Helm/StatefulSet 部署冲突
# 版本: 1.0.0
# 作者: 自动化运维团队
# 更新时间: 2026-02-19
# ===================================================

# ------------------------------
# Bash 安全模式
# ------------------------------
set -Eeuo pipefail
# -E : 捕获 trap ERR
# -e : 遇到错误立即退出
# -u : 未定义变量视为错误
# -o pipefail : 管道命令返回非零则视为失败

# ------------------------------
# 环境变量及默认值
# ------------------------------
# Kubernetes Namespace
NAMESPACE=${NAMESPACE:-database}
# 应用标签 (用于选择 PostgreSQL Pod/PVC)
APP_LABEL=${APP_LABEL:-postgres}

# ------------------------------
# Step 0: 清理已有 PVC
# ------------------------------
echo "=== Step 0: 清理已有 PVC/PV ==="

# 获取指定 Namespace 下，匹配 app 标签的所有 PVC 并删除
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
# -r : 当 xargs 输入为空时，不执行 delete 命令

# ------------------------------
# Step 0: 清理已有 PV
# ------------------------------
# 删除所有以 postgres-pv- 开头的 PV
kubectl get pv -o name | grep postgres-pv- | xargs -r kubectl delete || true
# || true : 防止 grep 没有匹配时退出脚本

# ------------------------------
# 完成提示
# ------------------------------
echo "✅ PVC/PV 清理完成"
