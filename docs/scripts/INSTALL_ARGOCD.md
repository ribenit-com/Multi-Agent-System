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

