# 🚀 ArgoCD Enterprise 自动安装脚本说明书

## 📌 项目简介

本脚本用于在 Kubernetes 集群中自动部署 ArgoCD 企业环境，支持自动检测环境、自动安装 Helm、自动部署 ArgoCD，并生成企业级成功页面。

脚本特点：

- ✅ 自动检测 Kubernetes
- ✅ 自动安装 Helm（如未安装）
- ✅ 自动添加 Argo Helm 仓库
- ✅ 自动创建 Namespace
- ✅ 自动执行 install / upgrade
- ✅ 自动开放防火墙端口
- ✅ 自动获取初始 admin 密码
- ✅ 自动生成企业级成功页面
- ✅ 支持幂等执行（可重复运行）

---

# 🏗 执行逻辑说明

脚本内部执行流程如下：

参数校验
↓
检测 kubectl
↓
检测 Kubernetes
↓
检测 Helm（不存在则自动安装）
↓
添加 Helm Repo
↓
创建 Namespace
↓
生成 values.yaml
↓
helm upgrade --install
↓
等待 Pod 就绪
↓
获取初始密码
↓
开放防火墙端口
↓
生成成功页面



---

# ⚙️ 环境要求

| 组件 | 要求 |
|------|------|
| 操作系统 | Linux (Ubuntu / CentOS / Debian) |
| Kubernetes | 已安装并运行 |
| kubectl | 已正确配置 |
| 网络 | 可访问外网下载 Helm 和 Chart |

---

# 🚀 安装方式

## 一键下载并执行

```bash
curl -fsSL https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/deploy/install_argocd_enterprise.sh \
-o install_argocd_enterprise.sh \
&& chmod +x install_argocd_enterprise.sh \
&& sudo ./install_argocd_enterprise.sh 30099 30100

./install_argocd_enterprise.sh <HTTP_PORT> <HTTPS_PORT>

访问地址: https://服务器IP:30100
用户名: admin
密码: xxxxxxxx
| 参数         | 说明                    |
| ---------- | --------------------- |
| HTTP_PORT  | ArgoCD HTTP NodePort  |
| HTTPS_PORT | ArgoCD HTTPS NodePort |
⚠ NodePort 范围必须为：30000-32767

示例：
sudo ./install_argocd_enterprise.sh 30099 30100


🌐 部署完成后

执行完成后终端会输出：
访问地址: https://服务器IP:30100
用户名: admin
密码: xxxxxxxx
🌐 部署完成后

执行完成后终端会输出：

访问地址: https://服务器IP:30100
用户名: admin
密码: xxxxxxxx


成功页面生成路径：

/mnt/truenas/argocd_success.html


浏览器访问：

https://<服务器IP>:30100


⚠ 首次访问可能提示 HTTPS 证书警告，属于正常现象。

🔁 幂等执行说明

脚本支持重复执行：

已安装 → 自动 upgrade

namespace 存在 → 自动跳过

repo 存在 → 自动跳过

不会重复创建资源。

🔥 Helm 自动安装机制

如果系统未安装 Helm，脚本会：

下载指定版本 Helm

解压

安装到 /usr/local/bin/helm

赋予执行权限

无需人工干预。

🛡 防火墙说明

脚本自动检测并开放端口：

ufw

firewalld

开放端口包括：

HTTP NodePort

HTTPS NodePort

❓ 常见问题
1️⃣ kubectl 未安装

检查：

kubectl version

2️⃣ Kubernetes 未运行

检查：

kubectl cluster-info

3️⃣ 端口无法访问

检查防火墙：

sudo ufw status


或：

firewall-cmd --list-ports

🗑 卸载方法
helm uninstall argocd -n argocd
kubectl delete ns argocd

🏷 版本信息
Enterprise v2.0.0
🏁 总结

本脚本适用于：

企业标准化部署

DevOps 环境初始化

GitOps 平台搭建

内部交付模板

如需扩展版本：

自动安装 K3s

自动安装 Kubernetes

支持 Ingress + 域名

支持自动卸载

支持离线部署

可继续扩展为完整企业发布安装器。

