#!/bin/bash
# network.sh: 二级菜单示例

# 脚本数组：name:description:command
options=(
    "ping_google:测试Google连通性:ping -c 4 google.com"
    "check_iface:查看网卡信息:ifconfig"
)

# 显示二级菜单并选择
function select_script() {
    local idx=0
    while true; do
        clear
        echo "== 网络运维脚本 =="
        for i in "${!options[@]}"; do
            name=$(echo "${options[$i]}" | cut -d':' -f1)
            desc=$(echo "${options[$i]}" | cut -d':' -f2)
            if [ $i -eq $idx ]; then
                echo -e "➤ $name - $desc"
            else
                echo "  $name - $desc"
            fi
        done
        echo
        echo "↑/↓选择  Enter执行  q返回上级"

        # 读取按键
        read -rsn1 key
        if [[ $key == $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key == '[A' ]]; then  # 上
                ((idx--))
                [ $idx -lt 0 ] && idx=$((${#options[@]}-1))
            elif [[ $key == '[B' ]]; then  # 下
                ((idx++))
                [ $idx -ge ${#options[@]} ] && idx=0
            fi
        elif [[ $key == "" ]]; then  # Enter
            cmd=$(echo "${options[$idx]}" | cut -d':' -f3)
            clear
            echo "执行: $cmd"
            eval "$cmd"
            read -p "按任意键返回..." -n1
        elif [[ $key == "q" ]]; then
            break
        fi
    done
}

select_script
