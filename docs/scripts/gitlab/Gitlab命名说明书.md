# 企业级 GitLab Kubernetes 命名规范说明书（生产标准化）

**版本：** 1.0 | **状态：** 生产可用
**适用范围：** 企业 DevOps / Kubernetes / GitLab 内网部署 / 边缘智能系统

---

## 1. 命名总体原则

**统一结构：**

```
<层级>-<系统/组件>-<角色/用途>[-<环境>]
```

| 规则 | 说明 |
| :-- | :-- |
| 大小写 | 全小写字母 |
| 连接符 | 使用 `-` 连接 |
| 禁止字符 | 禁止 `_` 与中文 |
| 缩写 | 禁止随意缩写，确保一致性 |
| 前缀 | 所有 GitLab 相关资源保持统一前缀 |

---

## 2. Kubernetes 资源命名规范

| 资源类型 | 规范名称 | 示例 | 说明 |
| :-- | :-- | :-- | :-- |
| Namespace | `ns-<层级>-<系统>-<环境>` | `ns-app-gitlab-prod` | `app` 层 + GitLab 组件 + 生产环境 |
| StatefulSet | `sts-<系统>` | `sts-app-gitlab` | StatefulSet 对应组件名称 |
| Service | `svc-<系统>` | `svc-app-gitlab` | NodePort 或 ClusterIP 服务统一命名 |
| CronJob | `cron-<系统>-<用途>` | `cron-app-gitlab-gc` | 定时任务，如 Registry GC |
| Secret | `secret-<系统>` | `secret-app-gitlab` | 保存组件机密信息 |
| Pod Label | `app-<系统>` | `app-gitlab` | Pod 标签统一，方便 Service 选择器匹配 |

---

## 3. GitLab 容器与 NodePort 命名

| 类型 | 命名 / 配置 | 说明 |
| :-- | :-- | :-- |
| HTTP NodePort | `30080` | 内网访问 HTTP |
| SSH NodePort | `30022` | 内网 SSH 访问 |
| Registry NodePort | `35050` | Docker 镜像推送/拉取 |

> NodePort 保留原端口号，可根据企业内网策略加防火墙限制访问。

---

## 4. PVC 与 StorageClass

| 项目 | 配置值 | 说明 |
| :-- | :-- | :-- |
| PVC 命名模板 | `data` | 由 StatefulSet 生成模板决定 |
| StorageClass | `sc-ssd-high` | 使用动态 PV |
| PVC 容量 | `200Gi` | 满足 Registry 镜像 + CI/CD 构建缓存需求 |
| `volumeMode` | `Filesystem` | — |
| `accessModes` | `ReadWriteOnce` | — |

---

## 5. CronJob 任务命名规范

| 项目 | 说明 |
| :-- | :-- |
| 命名规则 | `cron-<系统>-<用途>` |
| 示例 | `cron-app-gitlab-gc` |
| 用途 | 定期执行 GitLab Registry 垃圾回收，自动挂载 PVC 数据卷，确保数据一致性 |

---

## 6. 容器配置命名规范

| 配置项 | 命名 / 建议值 |
| :-- | :-- |
| GitLab 外部访问 URL | `http://gitlab.enterprise.local` |
| GitLab Registry URL | `http://192.168.1.100:35050` |
| Puma worker 数量 | `4` |
| PostgreSQL max connections | `100` |
| Memory requests | `6Gi` |
| CPU requests | `2000m` |
| Memory limits | `12Gi` |

---

## 7. 标准化命名收益

| 序号 | 收益 |
| :-- | :-- |
| 1 | 运维可快速识别资源归属 |
| 2 | CI/CD 自动化规则统一 |
| 3 | GitOps / ArgoCD 管理更清晰 |
| 4 | 支撑边缘设备 OTA 自动升级 |
| 5 | 支撑企业多模块扩展 |
| 6 | 降低命名冲突风险，提高集群可观测性 |

---

## 8. 核心总结

| 项目 | 说明 |
| :-- | :-- |
| 统一前缀 | Namespace / StatefulSet / Service / CronJob / Secret / Pod Label 全部统一前缀：`app-gitlab` |
| 端口管理 | NodePort 和 Registry 保留原有端口号，前缀与系统一致 |
| 标准化价值 | 确保 DevOps 自动化能力、集群可观测性、CI/CD 稳定性、边缘智能系统长期成长能力 |

> **命名标准化 = GitLab 组件可持续运维与企业 DevOps 可扩展能力**
