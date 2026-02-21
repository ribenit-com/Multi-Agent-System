# 一键上传 ArgoCD Git 仓库部署说明报告

- **脚本路径**：[deploy_one_command.sh](https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/tools/deploy_one_command.sh)
- **目标**：通过一键脚本将 Git 仓库添加到 ArgoCD 并创建必要的 Kubernetes ServiceAccount 和 SSH Secret，实现 GitOps 自动化部署的基础环境搭建。

---

## 1️⃣ 环境要求

| 类别 | 要求 |
|------|------|
| ArgoCD | 服务器已部署并可访问；ArgoCD CLI 已安装，并与服务端版本匹配 |
| Kubernetes | 有权限在 `argocd` 命名空间创建 ServiceAccount、RoleBinding 和 Secret |
| Git 仓库访问 | 支持 SSH Key 访问，或者提供个人访问令牌（PAT） |
| 本地 Shell 环境 | bash；kubectl 已配置并可以访问 Kubernetes 集群 |

---

## 2️⃣ 脚本执行前准备

设置 ArgoCD 管理员密码环境变量：

```bash
export ARGOCD_ADMIN_PASSWORD='你的admin密码'
```

确认 Git 仓库访问方式：SSH Key 可使用脚本自动生成并绑定到 ArgoCD；HTTPS PAT 可选，适用于非 SSH 仓库。

---

## 3️⃣ 脚本功能概览

| 功能 | 描述 |
|------|------|
| ServiceAccount | 创建或更新 ArgoCD 的 `gitlab-deployer-sa`，用于 CLI 或 API 访问 |
| RoleBinding | 给 ServiceAccount 分配 admin 权限 |
| SSH Secret | 创建或更新 `ssh-gitlab` Secret，用于 ArgoCD 拉取 Git 仓库 |
| CLI 登录 | 使用 `ARGOCD_ADMIN_PASSWORD` 登录 ArgoCD CLI |
| 仓库添加 | 添加 Git 仓库（SSH 或 HTTPS）到 ArgoCD，并自动检测是否已存在 |
| 仓库列表 | 显示 ArgoCD 当前已添加的仓库和状态 |

---

## 4️⃣ 脚本执行示例

```bash
# 下载脚本
curl -sSL https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/tools/deploy_one_command.sh -o deploy_one_command.sh

# 赋予执行权限
chmod +x deploy_one_command.sh

# 设置 ArgoCD 管理员密码
export ARGOCD_ADMIN_PASSWORD='jiahong565'

# 执行一键上传
./deploy_one_command.sh
```

**输出示例：**

```
🔹 创建/更新 ServiceAccount gitlab-deployer-sa ...
serviceaccount/gitlab-deployer-sa configured
rolebinding.rbac.authorization.k8s.io/gitlab-deployer-sa-binding configured
🔹 创建/更新 ArgoCD SSH Secret: ssh-gitlab ...
secret/ssh-gitlab configured
🔹 登录 ArgoCD CLI ...
'admin:login' logged in successfully
Context '192.168.1.10:30100' updated
🔹 添加或更新 Git 仓库 git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git ...
Repository 'git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git' added
🔹 当前 ArgoCD 仓库列表:
TYPE  NAME    REPO                                                                INSECURE  OCI    LFS    CREDS  STATUS      MESSAGE  PROJECT
git   gitlab  git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git      false     false  false  false  Successful
🎉 一键部署完成
```

---

## 5️⃣ 关键环境变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ARGOCD_SERVER` | `192.168.1.10:30100` | ArgoCD 服务地址 |
| `ARGOCD_NAMESPACE` | `argocd` | ArgoCD 所在 Kubernetes 命名空间 |
| `GITLAB_USER` | `ribenit-com` | Git 用户名（HTTPS 用） |
| `GITLAB_PAT` | 空 | Git 个人访问令牌（HTTPS 用） |
| `REPO_URL` | `git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git` | 需要添加的 Git 仓库 URL |
| `ARGO_APP` | `gitlab` | 在 ArgoCD 中标识该仓库的名称 |

> 注意：对 SSH 仓库，脚本会自动生成 Secret 并绑定，不需要设置 PAT。

---

## 6️⃣ 常见问题与解决方法

| 问题 | 原因 | 解决方法 |
|------|------|---------|
| HTTP 401 / 500 错误 | Token 未配置或不支持密码认证 | 使用 SSH Key，确保 Secret 已创建 |
| CLI 登录失败 | 未设置 `ARGOCD_ADMIN_PASSWORD` | 设置环境变量再执行脚本 |
| 仓库重复添加 | — | 脚本会自动检测是否存在，避免重复添加 |

---

## 7️⃣ 后续操作建议

**自动同步应用**，可在脚本后增加 ArgoCD Application 创建和同步命令：

```bash
argocd app create my-app \
  --repo git@github.com:ribenit-com/Multi-Agent-k8s-gitops-postgres.git \
  --path ./deploy \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated
```

**Token 管理**：建议保存 SSH Key 和 admin token，用于 CI/CD 自动化。

**脚本维护**：如果 ArgoCD CLI 更新，可能需要调整脚本参数，确保 `argocd version` 与服务器兼容。

---

## ✅ 总结

一键脚本成功实现：ArgoCD CLI 登录、Git 仓库添加（SSH 方式）、ServiceAccount 和 RoleBinding 创建、SSH Secret 创建、仓库状态校验。可以作为 GitOps 自动化部署的基础环境。
