#!/bin/bash

# =============================================
# 一键检测 agent01（20）重启后状态
# 包含：
# 1. edgecore 服务状态
# 2. edgecore 日志最近成功/错误信息
# 3. cloudcore 节点注册状态
# 
# 结果说明：
# - EdgeCore is running ✅  → edgecore 服务正常
# - EdgeCore is NOT running ❌  → 需要 sudo systemctl start edgecore
# - Logs 中显示 connect/ success → 已成功注册 cloudcore
# - Logs 中显示 error/fail → edgecore 未能连接 cloudcore
# - Master 上节点 Ready → agent01 正常工作
# - Master 上节点 NotReady → edgecore 未连接或网络异常
# =============================================

echo "=== Step 1: EdgeCore Service Status ==="
if systemctl is-active --quiet edgecore; then
    echo "EdgeCore is running ✅"
else
    echo "EdgeCore is NOT running ❌"
    echo "Try: sudo systemctl start edgecore"
fi

echo ""
echo "=== Step 2: EdgeCore Logs Check (last 20 lines) ==="
echo "Looking for cloudcore connection success or errors..."
# 提取关键日志
journalctl -u edgecore -n 20 --no-pager | grep -E "connect|error|fail|success" || echo "No recent connect/fail logs found"

echo ""
echo "=== Step 3: CloudCore Node Status from Master ==="
echo "This checks how Kubernetes master sees this node."
echo "Expected output: agent01 Ready ✅"
ssh zdl@192.168.1.10 "kubectl get nodes | grep agent01" || echo "Cannot reach master or node not found ❌"

echo ""
echo "=== Step 4: Quick Analysis Guide ==="
echo "- If EdgeCore is running and logs show 'register edge node success' and master shows Ready → Node is healthy ✅"
echo "- If EdgeCore is NOT running → Start edgecore and recheck"
echo "- If logs show error/fail → check network between agent01 and master (cloudcore)"
echo "- If master shows NotReady → edgecore may not have registered, or network issue, wait 30-60s"
echo "- If multiple errors persist → check edgecore.yaml for nodeID, cloudcore address, firewall rules"
