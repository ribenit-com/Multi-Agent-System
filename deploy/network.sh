#!/bin/bash

# 脚本数组：name:description:command
options=(
    "ping_google:测试Google连通性:ping -c 4 google.com"
    "check_iface:查看网卡信息:ifconfig"
)

echo "== 网络运维 =="
i=1
for opt in "${options[@]}"; do
    name=$(echo "$opt" | cut -d':' -f1)
    desc=$(echo "$opt" | cut -d':' -f2)
    echo "$i) $name - $desc"
    ((i++))
done

read -p "选择脚本编号: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#options[@]}" ]; then
    echo "选择无效"
    exit 1
fi

cmd=$(echo "${options[$((choice-1))]}" | cut -d':' -f3)
echo "执行: $cmd"
eval "$cmd"
