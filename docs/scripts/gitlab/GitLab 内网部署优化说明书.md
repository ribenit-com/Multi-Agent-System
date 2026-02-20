# GitLab 内网部署优化说明书

---

## 一、总体目标

该 YAML 文件是针对**中小团队（10–20 人）**内网 GitLab + Registry + CI/CD 场景优化的部署方案，兼顾稳定性、安全性和可扩展性，特别适合 KubeEdge 或单节点集群环境。

| 序号 | 主要优化点 |
| :-- | :-- |
| 1 | 资源配置优化，支撑并发 CI/CD |
| 2 | 健康探针完善，提高 Pod 稳定性 |
| 3 | 存储容量和模式优化，满足 Registry 和 CI/CD 大容量需求 |
| 4 | 安全性增强（Secret 管理、NodePort 限制） |
| 5 | CronJob GC 保证 Registry 清理可靠 |
| 6 | 外部访问留有 Ingress/TLS 扩展方案 |

---

## 二、各模块优化说明

### 1. Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ns-gitlab
```

| 项目 | 说明 |
| :-- | :-- |
| 作用 | 隔离 GitLab 资源，便于运维管理 |
| 优化意义 | 所有 GitLab 组件统一放在单一 Namespace 中，避免与其他服务冲突 |

---

### 2. Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-secrets
  namespace: ns-gitlab
stringData:
  root-password: "ReplaceWithStrongRandomPassword123!"
```

| 优化点 | 说明 |
| :-- | :-- |
| 原问题 | 明文 root 密码存在安全风险 |
| 建议方案 | 使用随机生成密码，或通过 Secret Manager / Vault 管理 |
| 持久化 | 保证 Pod 重启后仍可读取密码 |

---

### 3. StatefulSet

```yaml
replicas: 1
resources:
  requests:
    memory: "6Gi"
    cpu: "2000m"
  limits:
    memory: "12Gi"
```

**资源配置：**

| 项目 | 配置值 | 说明 |
| :-- | :-- | :-- |
| CPU | 2000m（2 核） | 支撑 10–20 人并发 CI/CD |
| Memory requests | 6 Gi | 基础保障 |
| Memory limits | 12 Gi | 峰值上限 |
| Puma worker | 4 个 | 提升 Web 并发能力 |
| PostgreSQL 最大连接 | 100 | 满足中小团队需求 |

**健康探针：**

| 探针类型 | 作用 |
| :-- | :-- |
| `startupProbe` | 避免 Pod 启动过早被判定失败 |
| `livenessProbe` | Pod 自愈 |
| `readinessProbe` | 负载均衡正确判断 |

**存储：**

| 项目 | 配置 |
| :-- | :-- |
| `volumeMode` | `Filesystem`（明确指定） |
| 存储容量 | 200 Gi |
| 用途 | Registry 镜像 + CI/CD 构建缓存 |

**副本策略：**

| 场景 | 建议 |
| :-- | :-- |
| 内网小团队 | 单副本，避免复杂 HA 配置 |
| 高可用需求 | 分离 PostgreSQL / Redis 并增加副本 |

---

### 4. Service（NodePort）

```yaml
type: NodePort
ports:
- http: 30080
- ssh: 30022
- registry: 35050
```

| 端口 | 用途 | 说明 |
| :-- | :-- | :-- |
| 30080 | HTTP | 内网 Web 访问 |
| 30022 | SSH | 建议限制为内网访问 |
| 35050 | Registry | Docker 镜像推送/拉取 |

**安全建议：**

| 方案 | 说明 |
| :-- | :-- |
| 外部访问 | 推荐 Ingress + HTTPS |
| 内网访问 | NodePort 结合防火墙或网络策略限制 |

---

### 5. CronJob（Registry GC）

```yaml
schedule: "0 3 * * 0"
command: ["/bin/sh", "-c", "gitlab-ctl registry-garbage-collect -m"]
```

| 项目 | 说明 |
| :-- | :-- |
| 执行周期 | 每周日凌晨 3 点 |
| 作用 | 定时清理 Docker Registry 垃圾镜像，防止磁盘膨胀 |
| 数据一致性 | 通过 `volumeMounts` 挂载 PVC 保障 |
| 失败策略 | `restartPolicy: OnFailure` 自动重试 |
| 扩展建议 | 大 Registry 可考虑独立 Pod 或单独 GC Runner |

---

### 6. 可选 Ingress / TLS

```yaml
# 开启外部 HTTPS 访问可使用 Nginx Ingress + Cert-Manager
```

| 项目 | 说明 |
| :-- | :-- |
| 外部访问 | 保留配置模板，使用 TLS 证书保障安全 |
| 联合使用 | 可与 NodePort 结合，实现外网访问与内网管理分离 |

---

### 7. 总体安全性优化

| 安全措施 | 说明 |
| :-- | :-- |
| Secret 管理 | 使用随机密码或 Secret Manager |
| NodePort 限制 | 限制为内网访问 |
| 网络策略 | HTTP / SSH / Registry 结合防火墙限制 |
| 外部 HTTPS | 建议使用 Ingress + Cert-Manager |

---

### 8. 适用场景

| 场景 | 说明 |
| :-- | :-- |
| 团队规模 | 内网中小团队，CI/CD 并发 10–20 人 |
| 部署模式 | 单节点 StatefulSet |
| 边缘访问 | KubeEdge 边缘节点访问 |
| 扩展方向 | HA / Ingress + TLS / 存储扩容 / 分布式部署 |

---

> 该优化 YAML 在保证稳定性、可靠性和安全性的前提下，适合生产环境内网使用，能够支撑中小团队 GitLab + CI/CD + Registry 的日常工作，同时预留了扩展空间（Ingress/TLS、存储扩容、HA 分布式部署）。
