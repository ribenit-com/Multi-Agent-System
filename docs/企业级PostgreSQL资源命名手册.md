============================================================
# 企业级 PostgreSQL HA 资源清单（Kubernetes） — 标准化命名版
版本: 1.1 | 状态: 生产可用
============================================================

## 1. Namespace
- **名称**: `ns-postgres-ha`
- **作用**: 存放 PostgreSQL HA 所有资源，实现资源隔离
- **备注**: 必须存在，脚本可自动创建

## 2. StatefulSet
- **名称**: `sts-postgres-ha`
- **作用**: HA 数据库核心控制器，管理 Pod 副本
- **副本数**: 2~3
- **备注**: Pod 自动命名为 `sts-postgres-ha-0`, `sts-postgres-ha-1` 等

## 3. Services
| 类型 | 名称 | 说明 |
|------|------|------|
| 主节点 | `svc-postgres-primary` | 主节点入口 Service，ClusterIP 类型，端口 5432 |
| 从节点 | `svc-postgres-replica` | 从节点 Service，ClusterIP 类型，端口 5432 |

## 4. PVC（PersistentVolumeClaim）
| 名称 | 说明 | 备注 |
|------|------|------|
| `pvc-postgres-ha-0` | 数据存储 | 绑定到 StatefulSet Pod 0 |
| `pvc-postgres-ha-1` | 数据存储 | 绑定到 StatefulSet Pod 1 |
| `pvc-postgres-ha-2` | 数据存储 | 绑定到 StatefulSet Pod 2（可选） |

- **StorageClass**: `sc-ssd-high`（高性能 SSD）  
- **访问模式**: `ReadWriteOnce`  
- **大小**: 根据需求定义，例如 10Gi~20Gi  

## 5. Pod
- **命名**: 由 StatefulSet 自动生成，例如 `sts-postgres-ha-0`、`sts-postgres-ha-1`  
- **作用**: 运行 PostgreSQL 实例  
- **备注**: Pod 与 PVC 一一绑定，保证数据持久化  

## 6. ConfigMap（可选）
- **名称**: `cm-postgres-config`
- **作用**: PostgreSQL 配置文件  
- **备注**: 挂载到 Pod，可覆盖默认配置  

## 7. Secret
- **名称**: `secret-postgres-password`
- **作用**: 数据库密码存储  
- **备注**: 必须加密，挂载到 Pod 环境变量  

## 8. NetworkPolicy（可选）
- **名称**: `np-postgres-ha`
- **作用**: 控制 Pod 间和 Service 的访问  
- **备注**: 建议生产环境使用，提高安全性  

## 9. StorageClass
- **名称**: `sc-ssd-high`
- **作用**: PVC 绑定 PV 的存储策略  
- **备注**: 高性能 SSD，保证数据库 IO 性能  

## 10. PersistentVolume (PV)
- **名称**: 自动绑定 PVC  
- **作用**: 数据持久化  
- **备注**: 由 StorageClass 自动管理  

---

## 命名规范总结（标准化版）

| 资源类型 | 命名规范示例 |
|----------|--------------|
| Namespace | `ns-postgres-ha` |
| StatefulSet | `sts-postgres-ha` |
| Service | `svc-postgres-primary` / `svc-postgres-replica` |
| PVC | `pvc-postgres-ha-0`、`pvc-postgres-ha-1`、`pvc-postgres-ha-2` |
| Pod | 自动生成：`sts-postgres-ha-0`、`sts-postgres-ha-1` |
| ConfigMap | `cm-postgres-config` |
| Secret | `secret-postgres-password` |
| NetworkPolicy | `np-postgres-ha` |
| StorageClass | `sc-ssd-high` |

---

## 推荐部署顺序（标准化版）

1. 创建 Namespace  
2. 创建 Secret（数据库密码）  
3. 创建 ConfigMap（可选）  
4. 创建 StorageClass（如果还没有）  
5. 创建 StatefulSet（HA 副本数量 2~3）  
6. 创建 Service（主、从节点）  
7. StatefulSet 自动生成 Pod 和 PVC  
8. 可选：创建 NetworkPolicy 进行访问控制  
9. 执行报告脚本生成 HTML 安装报告  

---

✅ **特点与优势**  
- 全拼 `postgres`，易识别、与其他模块（MySQL、Redis、MongoDB）完全区分  
- Pod、PVC、Service 命名一致，便于运维和监控  
- 适合企业级多模块 Kubernetes 集群  
- 支持 HA 副本扩展，PVC 和 Pod 一一绑定保证数据安全
