#!/bin/bash
# ============================================
# 简单NAS挂载检测脚本
# ============================================

NAS_PATH="/mnt/truenas"
TEST_FILE="$NAS_PATH/test_write_$(date +%s).txt"

echo "检测 NAS 挂载路径: $NAS_PATH"

# 1. 检查目录是否存在
if [ -d "$NAS_PATH" ]; then
    echo "✅ 目录存在: $NAS_PATH"
else
    echo "❌ 目录不存在: $NAS_PATH"
    exit 1
fi

# 2. 测试写入权限
if echo "测试写入 $(date)" > "$TEST_FILE"; then
    echo "✅ 可以写入文件: $TEST_FILE"
    # 测试完成后删除文件
    rm -f "$TEST_FILE"
else
    echo "❌ 无法写入文件: $NAS_PATH"
    exit 1
fi

echo "NAS 挂载检测完成，路径可用且可写。"
