# Moltbot - 餐饮业智能员工调度基盘

## 🌐 项目背景 (Project Background)

### 1. 行业现状与挑战
进入 2026 年，日本餐饮业正处于数字化转型的十字路口。虽然 AI 技术（如 ChatGPT, 各类 SaaS 工具）已广泛普及，但广大餐饮经营者（尤其是葛饰区等地的中小店主）正面临着**“数字化疲劳”**：
* **AI 员工孤岛化：** 老板购买了记账 AI、排班 AI 和营销 AI，但这些工具互不通信。老板不得不充当“人工接口”，在不同 App 之间手动搬运数据。
* **合规成本激增：** 随着《电子账簿保存法》和 Invoice 制度的全面强制执行，每日繁琐的领收书（收据）分类、汇总与 PDF 合规化保存成为了沉重的负担。
* **技术落地门槛高：** 传统的云端方案在后厨等复杂环境下存在网络延迟及隐私安全顾虑，且缺乏懂行（餐饮 Know-how）的逻辑层。

### 2. Moltbot 的核心理念
**Moltbot** 不是另一个单一的 AI 工具，而是一个基于 **KubeEdge + Kubernetes (K8s)** 架构设计的**“智能员工调度基盘”**。

它的核心逻辑是：**“让 AI 员工像正规军一样协同工作。”**
* **智能调度（Orchestration）：** 利用 n8n 等自动化引擎，将美食协会沉淀的行业经验转化为“调度剧本”。当老板“拍照上传一张领收书”时，系统会自动唤醒财务 AI 进行分类、唤醒合规 AI 进行审计、唤醒经营 AI 进行利润汇总。
* **云边协同（Cloud-Edge Synergy）：** 通过 KubeEdge 将计算能力下沉到店面现场。领收书的 OCR 识别、视频监控分析等高隐私任务在**边缘端**处理，而复杂的策略分析则在**云端**协同。
* **省力化（Labor-saving）导向：** 我们的目标是将店主从深夜理票、反复核对的杂务中解脱出来，将每天 1 小时的财务处理时间缩减至 1 分钟的“随手拍”。

### 3. 本项目结构说明
基于仓库中的核心文件，本项目提供了完整的基盘部署方案：
* **`deploy/` (核心部署)：** 提供生产级 `n8n` 自动化流引擎部署及 `containerd` 边缘环境安装脚本，确保调度中枢稳固。
* **`docs/` (设计文档)：** 详细记录了针对餐饮场景的系统架构设计，包括如何通过 AI 调度实现领收书的自动分类与汇总。
* **`scripts/` (运维辅助)：** 提供日常维护所需的脚本工具，降低非技术人员的运维门槛。

---

> **使命：** 结合美食协会的行业智慧与云原生技术，为日本餐饮业打造一套“永不疲倦、精通规矩、自动协作”的数字总管基盘。
## 📊 目录说明

| 目录 | 用途 | 重要性 |
|------|------|--------|
| `deploy/` | 所有部署脚本，按服务分类 | ⭐⭐⭐⭐⭐ |
| `docs/` | 完整文档体系，从入门到精通 | ⭐⭐⭐⭐⭐ |
| `scripts/` | 日常运维辅助脚本 | ⭐⭐⭐⭐ |
| `tests/` | 确保代码质量 | ⭐⭐⭐ |
| `examples/` | 帮助用户快速上手 | ⭐⭐⭐ |
| `.github/` | 社区协作规范 | ⭐⭐ |

## 🎯 核心文件说明

### 根目录文件
| 文件 | 作用 |
|------|------|
| `README.md` | 项目总入口，快速了解项目 |
| `LICENSE` | MIT 许可证，明确使用权限 |
| `.gitignore` | 忽略不需要版本控制的文件 |
| `SECURITY.md` | 安全漏洞报告流程 |

### deploy/ 核心脚本
| 脚本 | 位置 | 作用 |
|------|------|------|
| `install-containerd-edge.sh` | `deploy/containerd/` | 边缘节点安装 containerd |
| `deploy-n8n-stable.sh` | `deploy/n8n/` | 生产环境部署 n8n |
| `backup-n8n.sh` | `deploy/n8n/` | 定时备份 n8n 数据 |
| `utils.sh` | `deploy/common/` | 颜色定义、日志函数等工具 |

### docs/ 核心文档
| 文档 | 位置 | 作用 |
|------|------|------|
| `prerequisites.md` | `docs/installation/` | 硬件、软件要求 |
| `troubleshooting.md` | `docs/operations/` | 常见问题解决 |
| `system-design.md` | `docs/architecture/` | 系统架构设计 |
| `CHANGELOG.md` | `docs/versions/` | 完整版本历史 |

## 🔍 快速导航

笔记：
Redis 检测是否安装，因为dify控件要用
n8n  要先装PostgreSQL 再装n8n

企业级脚本的推进：

一、核心模块清单（初期企业级）
模块	作用	部署方式
Kubernetes 集群	容器调度、Pod 管理	手动/自动脚本
KubeEdge	边缘节点管理、调度机器人	脚本安装 + Config
ArgoCD	GitOps 部署控制中心 & 应用	Helm + 脚本
PostgreSQL	中央数据库，存储任务/状态/日志	Helm + 脚本
Redis	任务队列/缓存，支持 n8n/Worker	Helm + 脚本
n8n	工作流引擎（调度机器人任务）	Helm + ArgoCD 管理
Dify	AI Agent / 企业助手平台	Helm + ArgoCD 管理
Worker	边缘任务处理	Helm + ArgoCD 管理
Edge Agent	部署到边缘节点，执行机器人命令	Helm + ArgoCD 管理

⚠ 注意：初期不需要 HA、多副本，单节点即可，只要方向正确。

二、模块安装顺序（脚本顺序）

基础设施

Kubernetes 集群

KubeEdge

ArgoCD

PostgreSQL

Redis（单实例）

应用层（后续通过 ArgoCD 管理）

n8n

Dify

Worker

Edge Agent

三、企业级安装脚本思路

每个模块都可以写一个 Bash 企业级脚本，特点：

✅ 参数校验（端口、路径、节点）

✅ 环境检查（kubectl、helm、node）

✅ Helm 安装 / 升级

✅ Namespace 自动创建

✅ PVC / Volume 配置

✅ 防火墙端口自动开放

✅ 成功日志/HTML页面输出

1️⃣ ArgoCD 安装脚本（参考你之前的脚本）

参数：HTTP_PORT, HTTPS_PORT, NAMESPACE

功能：

检查 kubectl / helm

创建 namespace

helm upgrade --install argo/argo-cd

rollout status

生成 HTML 成功页

2️⃣ PostgreSQL 安装脚本（企业级）

参数：DB_NAME, USER, PASSWORD, NAMESPACE, STORAGE_SIZE

功能：

检查 helm / kubectl

创建 namespace

生成 values.yaml

helm upgrade --install postgresql bitnami/postgresql -f values.yaml

等待 pod ready

输出访问信息（host/port/user/password）

3️⃣ Redis 安装脚本（初期单实例即可）

功能：

Helm 安装 bitnami/redis

Namespace 创建

Pod 就绪检测

输出 host/port/password

4️⃣ n8n / Dify / Worker / Edge Agent 安装脚本

不直接用脚本安装

通过 ArgoCD Application 管理

脚本作用：

生成 Helm values.yaml

创建 ArgoCD Application yaml

apply 到 ArgoCD

四、注意事项（企业级基线）

数据库集中管理：PostgreSQL 放中央服务器，Edge 只做 Agent

n8n 无状态：用 PostgreSQL 存储状态，方便横向扩展

日志与监控：初期只要 pod logs + kubectl get pod

防火墙：自动开放 ArgoCD / n8n / Redis / PostgreSQL 端口

GitOps：一切应用都通过 ArgoCD 部署

五、总结安装流程（企业级初期版）
1️⃣ 脚本安装 Kubernetes + KubeEdge
2️⃣ 脚本安装 ArgoCD
3️⃣ 脚本安装 PostgreSQL
4️⃣ 脚本安装 Redis
5️⃣ ArgoCD 管理：
    - n8n
    - Dify
    - Worker
    - Edge Agent


这种流程保证：

初期稳定

GitOps 扩展不踩坑

未来升级 HA / 多副本直接接入


