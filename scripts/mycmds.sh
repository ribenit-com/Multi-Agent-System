#!/bin/bash
# 一级菜单：分类选择

categories_dir="$HOME/mycmds/categories"
categories=($(ls "$categories_dir"))

echo "== 一级菜单: 功能分类 =="
i=1
for cat in "${categories[@]}"; do
    echo "$i) ${cat%.sh}"
    ((i++))
done

read -p "选择分类编号: " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#categories[@]}" ]; then
    echo "选择无效"
    exit 1
fi

# 执行二级菜单脚本
bash "$categories_dir/${categories[$((choice-1))]}"
