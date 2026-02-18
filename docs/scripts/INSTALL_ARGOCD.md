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
