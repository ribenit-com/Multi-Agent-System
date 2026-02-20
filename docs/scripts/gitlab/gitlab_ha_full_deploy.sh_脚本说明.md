# HeliosGuard 验证逻辑说明书
脚本名称: HeliosGuard
原名称: gitlab_ha_full_deploy.sh
版本: v1.0
用途: GitLab HA 部署前后合规验证逻辑说明

============================================================

# 1. 脚本定位

HeliosGuard 是用于 GitLab HA 架构部署过程中的合规验证模块。

本脚本不负责业务逻辑。
本脚本专注于：

- 命名规范校验
- 资源存在性校验
- 资源健康状态校验
- 合规分级输出

============================================================

# 2. 验证逻辑总览

验证逻辑分为五层结构：

1️⃣ Namespace 层验证  
2️⃣ 控制器层验证（StatefulSet / Deployment）  
3️⃣ 服务层验证（Service）  
4️⃣ 存储层验证（PVC）  
5️⃣ 运行层验证（Pod 状态）  

============================================================

# 3. Namespace 验证逻辑

3.1 验证目标

确保 HA 环境命名符合企业规范。

3.2 标准格式

ns-<layer>-<system>-<env>

示例：

ns-mid-storage-prod
ns-app-gitlab-prod

3.3 验证规则

- Namespace 是否存在
- 是否符合命名规范
- 是否使用非法字符
- 是否混用缩写

3.4 违规等级

不存在 → error  
命名不规范 → error  

============================================================

# 4. 控制器层验证逻辑

4.1 验证对象

- StatefulSet
- Deployment

4.2 验证目标

确保 HA 核心控制器存在且命名标准化。

4.3 标准示例

sts-gitlab-ha
dep-gitlab-web

4.4 验证规则

- 控制器是否存在
- 是否多实例冲突
- 是否命名符合规范
- 是否存在遗留旧版本控制器

4.5 违规分类

missing      → error  
naming       → error  
redundant    → warning  

============================================================

# 5. Service 验证逻辑

5.1 验证目标

确保 HA 架构对外通信通道存在。

5.2 标准示例

svc-gitlab-web
svc-gitlab-ssh
svc-gitlab-api

5.3 验证规则

- Service 是否存在
- 类型是否符合设计（ClusterIP / LoadBalancer）
- 端口是否正确
- 是否命名一致

5.4 违规等级

不存在 → error  
端口错误 → error  
命名不规范 → error  

============================================================

# 6. PVC 存储验证逻辑

6.1 验证目标

确保数据持久化符合 HA 架构要求。

6.2 标准格式

pvc-gitlab-ha-<index>

正则规则：

^pvc-gitlab-ha-[0-9]+$

6.3 验证规则

- PVC 是否存在
- 是否与 StatefulSet 数量匹配
- 命名是否规范
- 是否存在历史残留 PVC

6.4 违规等级

不存在 → error  
命名不规范 → warning  
数量不匹配 → error  

============================================================

# 7. Pod 健康验证逻辑

7.1 验证目标

确保 GitLab HA 实例全部健康运行。

7.2 检测条件

Pod Status == Running

异常状态包括：

Pending
CrashLoopBackOff
Error
Terminating
Unknown

7.3 违规等级

非 Running 状态 → error  

============================================================

# 8. 合规分级模型

8.1 等级定义

error
  阻断级问题
  不允许继续部署

warning
  风险级问题
  可继续部署但必须记录

ok
  完全合规

------------------------------------------------------------

8.2 优先级规则

若存在 error → 总体状态 = error  
若无 error 但存在 warning → 总体状态 = warning  
否则 → ok  

============================================================

# 9. 输出结构说明

标准 JSON 输出结构：

{
  "summary": {
    "status": "error|warning|ok",
    "error_count": 0,
    "warning_count": 0
  },
  "details": [
    {
      "resource_type": "",
      "name": "",
      "status": "",
      "severity": "",
      "category": ""
    }
  ]
}

字段说明：

resource_type
  Kubernetes 资源类型

name
  资源名称

status
  当前检测结果

severity
  error / warning

category
  missing / naming / unhealthy / redundant

============================================================

# 10. 验证执行时机

HeliosGuard 验证在以下阶段执行：

1. GitLab HA 部署前预检
2. GitLab HA 部署后验收
3. CI/CD Pipeline 阶段 Gate
4. 定时巡检任务

============================================================

# 11. 核心原则

HeliosGuard 的验证逻辑遵循：

- 命名标准化优先
- 资源完整性优先
- 健康状态优先
- 阻断级问题绝不放行

============================================================

# 12. 结论

HeliosGuard 是 gitlab_ha_full_deploy.sh 的验证核心模块。

其职责仅限于：

验证合规  
输出等级  
阻断风险  

不负责业务执行。

============================================================
