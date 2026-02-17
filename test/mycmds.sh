#!/bin/bash
# 一级菜单：功能分类

categories_dir="$HOME/mycmds/categories"
categories=($(ls "$categories_dir"))

idx=0
while true; do
    clear
    echo "== 一级菜单: 功能分类 =="
    for i in "${!categories[@]}"; do
        cat_name="${categories[$i]%.sh}"
        if [ $i -eq $idx ]; then
            echo -e "➤ $cat_name"
        else
            echo "  $cat_name"
        fi
    done
    echo
    echo "↑/↓选择  Enter进入分类  q退出"

    read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 key
        if [[ $key == '[A' ]]; then
            ((idx--))
            [ $idx -lt 0 ] && idx=$((${#categories[@]}-1))
        elif [[ $key == '[B' ]]; then
            ((idx++))
            [ $idx -ge ${#categories[@]} ] && idx=0
        fi
    elif [[ $key == "" ]]; then
        bash "$categories_dir/${categories[$idx]}"
    elif [[ $key == "q" ]]; then
        clear
        exit 0
    fi
done
