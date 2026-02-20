============================================================
# 企业级 GitLab 命名规则手册（标准化版）
版本: 1.0 | 状态: 生产可用
适用范围: 企业 DevOps / Kubernetes / 边缘智能系统
============================================================

## 1. 总体设计原则

### 1.1 统一命名结构

采用统一结构：

```
<层级>-<系统/组件>-<角色/用途>[-<环境>]
```

规则说明：

- 全小写字母
- 使用 `-` 连接
- 禁止使用 `_`
- 禁止中文
- 禁止随意缩写（必须统一规范）

---

## 2. Group（组织）命名规范

### 2.1 格式

```
grp-<层级>-<领域>
```

### 2.2 示例

| 层级 | Group 名称 | 说明 |
|------|------------|------|
| 系统层 | grp-sys-infra | 集群基础设施 |
| 中间件层 | grp-mid-storage | 数据库与存储 |
| 应用层 | grp-app-workflow | 业务与工作流 |
| AI层 | grp-mod-ai | 模型与推理系统 |
| 边缘层 | grp-edge-runtime | 边缘计算系统 |

---

## 3. Project（仓库）命名规范

### 3.1 格式

```
repo-<组件名>-<角色>
```

或

```
repo-<系统名>
```

### 3.2 Kubernetes 相关示例

| 组件 | 仓库名称 |
|------|----------|
| PostgreSQL HA | repo-postgres-ha |
| Redis Cluster | repo-redis-cluster |
| n8n Workflow | repo-n8n-engine |
| Dify AI | repo-dify-server |
| Ollama Engine | repo-ollama-engine |

---

## 4. Branch 分支命名规范

### 4.1 主分支

| 类型 | 名称 |
|------|------|
| 主分支 | main |
| 生产发布 | release |
| 开发分支 | develop |

---

### 4.2 功能分支

```
feat-<功能名>
fix-<问题名>
refactor-<模块名>
hotfix-<紧急问题>
```

示例：

```
feat-replica-autosync
fix-pvc-cleanup-bug
hotfix-password-leak
```

---

## 5. Tag（版本标签）规范

### 5.1 格式

```
v<主版本>.<次版本>.<修订号>
```

示例：

```
v1.0.0
v1.1.2
v2.0.0
```

如为 HA 版本：

```
v1.0.0-ha
```

---

## 6. CI/CD 命名规范

### 6.1 Pipeline 名称

```
ci-<组件名>
```

示例：

```
ci-postgres-ha
ci-edge-runtime
```

---

### 6.2 Runner 命名

```
runner-<用途>-<环境>
```

示例：

```
runner-build-prod
runner-edge-dev
runner-ai-gpu
```

---

## 7. Docker 镜像命名规范

### 7.1 格式

```
registry.example.com/<项目路径>/<组件>:<版本>
```

示例：

```
registry.enterprise.com/mid-storage/postgres-ha:v1.0.0
registry.enterprise.com/mod-ai/ollama-engine:v2.1.0
```

---

## 8. Kubernetes 对应关系规范

GitLab 仓库名称必须与 Kubernetes 资源统一。

| GitLab Project | Kubernetes StatefulSet | Service |
|----------------|------------------------|----------|
| repo-postgres-ha | sts-postgres-ha | svc-postgres-primary |
| repo-redis-cluster | sts-redis-cluster | svc-redis-master |
| repo-n8n-engine | dep-n8n-engine | svc-n8n-api |

---

## 9. 环境区分规范

### 9.1 分支区分

- main → 生产
- develop → 测试
- feat-* → 功能开发

### 9.2 Namespace 区分

```
ns-mid-storage-prod
ns-mid-storage-dev
ns-mid-storage-test
```

---

## 10. 镜像同步命名策略（GitLab ↔ GitHub）

为支撑边缘智能系统成长，建议：

| 平台 | 角色 |
|------|------|
| GitLab | 企业主仓 |
| GitHub | 全球镜像仓 |

镜像仓库名称保持一致：

```
repo-postgres-ha
repo-edge-runtime
repo-ai-agent
```

避免因仓库命名不同导致 CI 或 OTA 升级路径失效。

---

## 11. 禁止行为

- ❌ 使用随意命名
- ❌ 使用个人缩写
- ❌ 同一组件多种拼写（postgres / postgresql 混用）
- ❌ 不带前缀直接创建仓库
- ❌ 同一组件多个命名风格并存

---

## 12. 标准化收益

- 运维快速识别资源归属
- CI/CD 自动化规则统一
- GitOps 管理更清晰
- ArgoCD 可视化清晰
- 支撑边缘设备 OTA 自动升级
- 支撑企业级多模块扩展

---

## 13. 核心结论

GitLab 命名规则不仅是规范问题。

它决定：

- DevOps 自动化能力
- 集群可观测性
- CI 稳定性
- 边缘智能系统长期成长能力

命名标准化 = 架构可持续化。

============================================================
