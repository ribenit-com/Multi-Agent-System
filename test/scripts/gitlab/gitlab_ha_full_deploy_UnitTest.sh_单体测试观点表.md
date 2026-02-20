# gitlab_ha_full_deploy_UnitTest.sh 单体测试观点表
文件: gitlab_ha_full_deploy_UnitTest.sh
版本: v1.0
适用对象: HeliosGuard v4.0
类型: 企业级验证逻辑单体测试矩阵

============================================================

# 1. 测试目标说明

本单体测试用于验证 HeliosGuard 的以下能力：

- 命名规范检测
- 资源存在性检测
- 资源健康状态检测
- 合规分级计算逻辑
- enforce 模式自动修复行为
- JSON 输出结构正确性

============================================================

# 2. 测试分层视图

测试按验证层级划分为五大模块：

1️⃣ Namespace 层  
2️⃣ Service 层  
3️⃣ PVC 层  
4️⃣ Pod 健康层  
5️⃣ 合规分级汇总层  

============================================================

# 3. 单体测试观点矩阵

| 编号 | 测试场景 | 输入条件 | 运行模式 | 预期 severity | 预期 summary | 预期行为 |
|------|----------|----------|----------|---------------|--------------|----------|
| UT-01 | Namespace 不存在 | kubectl get ns 返回 1 | audit | error | error | 终止深入检测 |
| UT-02 | Namespace 不存在 | kubectl get ns 返回 1 | enforce | warning | warning | 自动创建 Namespace |
| UT-03 | Service 不存在 | kubectl get svc 返回 1 | audit | error | error | 记录 missing |
| UT-04 | Service 不存在 | kubectl get svc 返回 1 | enforce | warning | warning | 自动创建 Service |
| UT-05 | PVC 命名不合法 | pvc 名称不匹配正则 | audit | warning | warning | 记录 naming |
| UT-06 | PVC 命名不合法 | pvc 名称不匹配正则 | enforce | warning | warning | 删除非法 PVC |
| UT-07 | Pod 状态异常 | Pod != Running | audit | error | error | 记录 unhealthy |
| UT-08 | Pod 状态异常 | Pod != Running | enforce | warning | warning | 删除异常 Pod |
| UT-09 | 全部资源正常 | 所有 kubectl 正常 | audit | 无 | ok | summary=ok |
| UT-10 | error + warning 混合 | 同时存在 error 与 warning | audit | error | error | error 优先 |
| UT-11 | 仅 warning | 仅存在 warning | audit | warning | warning | 正确汇总 |
| UT-12 | JSON 结构校验 | 输出 JSON | 任意 | 正确结构 | 正确结构 | 包含 summary 与 details |

============================================================

# 4. 覆盖维度说明

## 4.1 功能覆盖

- 资源存在性逻辑 ✔
- 正则命名校验 ✔
- 非 Running 状态判断 ✔
- 自动修复路径 ✔
- error/warning 优先级 ✔

## 4.2 分支覆盖

- Namespace 缺失分支 ✔
- Service 缺失分支 ✔
- PVC naming 分支 ✔
- Pod unhealthy 分支 ✔
- enforce 模式分支 ✔
- summary 计算分支 ✔

## 4.3 异常路径覆盖

- kubectl 返回非 0 ✔
- 空资源列表 ✔
- 无 json_entries 情况 ✔

============================================================

# 5. 合规等级计算验证观点

测试必须验证以下规则：

error_count > 0
    → summary.status = error

error_count = 0 且 warning_count > 0
    → summary.status = warning

error_count = 0 且 warning_count = 0
    → summary.status = ok

============================================================

# 6. JSON 输出结构验证观点

输出必须符合以下结构：

{
  "summary":{
      "status":"",
      "mode":"",
      "error_count":0,
      "warning_count":0
  },
  "details":[
      {
          "resource_type":"",
          "name":"",
          "status":"",
          "severity":"",
          "category":"",
          "action":"",
          "app":"PostgreSQL-HA"
      }
  ]
}

验证重点：

- summary 字段必须存在
- details 必须为数组
- severity 字段合法
- category 字段合法
- app 字段固定为 PostgreSQL-HA

============================================================

# 7. 测试通过判定标准

- 所有测试用例 PASS
- JSON 格式合法
- 无未捕获异常退出
- exit code 正确（失败时返回 1）

============================================================

# 8. 测试风险说明

以下场景不属于单体测试范围：

- 实际 Kubernetes API 通信
- 真实 PVC 数据删除风险
- RBAC 权限不足问题
- Helm 依赖逻辑

这些属于集成测试范围。

============================================================

# 9. 结论

gitlab_ha_full_deploy_UnitTest.sh 单体测试覆盖：

- 逻辑正确性
- 分支完整性
- 合规分级模型
- JSON 输出完整性

通过该测试矩阵，可满足企业级 CI Gate 审计要求。

============================================================
