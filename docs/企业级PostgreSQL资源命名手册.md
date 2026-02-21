# Kubernetes 企业命名规则（AI 执行版）

## 1️⃣ 命名公式

```
<前缀>-<模块名>-<角色>
```

## 2️⃣ 前缀映射

| 资源类型 | 前缀 |
| :-- | :-- |
| Namespace | `ns` |
| StatefulSet | `sts` |
| Service | `svc` |
| PVC | `pvc` |
| ConfigMap | `cm` |
| Secret | `secret` |
| NetworkPolicy | `np` |
| StorageClass | `sc` |

## 3️⃣ 角色规则

### HA 类资源

适用：Namespace / StatefulSet / PVC / Pod / NetworkPolicy

```
角色 = ha
```

### Service

```
svc-<模块名>-primary
svc-<模块名>-replica
```

### ConfigMap

```
cm-<模块名>-config
```

### Secret

```
secret-<模块名>-password
```

### PVC

```
pvc-<模块名>-ha-<编号>
```

编号从 `0` 开始。

## 4️⃣ 模块名规则

| 规则 | 说明 |
| :-- | :-- |
| 大小写 | 全小写 |
| 禁止词 | `test` / `demo` / `tmp` |
| 拼写 | 必须全拼 |

## 5️⃣ 示例（MODULE=gitlab）

| 资源类型 | 命名结果 |
| :-- | :-- |
| Namespace | `ns-gitlab-ha` |
| StatefulSet | `sts-gitlab-ha` |
| Service (主) | `svc-gitlab-primary` |
| Service (从) | `svc-gitlab-replica` |
| ConfigMap | `cm-gitlab-config` |
| Secret | `secret-gitlab-password` |
| NetworkPolicy | `np-gitlab-ha` |
| PVC | `pvc-gitlab-ha-0` |
