# check_gitlab_names_json.sh 单体测试说明书（v3.0）

**模块**：GitLab HA  
**类型**：Kubernetes 资源命名检测  
**性质**：功能型脚本，生成 `json_entries` + `calculate_summary` 输出  

---

# 一、单体测试观点表

| 编号 | 函数 | 场景 | 期望 |
|------|------|------|------|
| UT-01 | check_namespace | namespace audit 模式不存在 | json_entries 包含 error，summary=error |
| UT-02 | check_namespace | namespace enforce 模式不存在 | json_entries 包含 warning，summary=warning |
| UT-03 | check_service | service 不存在 | json_entries 包含 error，summary=error |
| UT-04 | check_pvc | pvc 命名不规范 | json_entries 包含 warning，summary=warning |
| UT-05 | check_pod | pod 非 Running | json_entries 包含 error，summary=error |
| UT-06 | calculate_summary | json_entries 中有 error + warning | summary=error |
| UT-07 | calculate_summary | json_entries 中仅 warning | summary=warning |
| UT-08 | calculate_summary | json_entries 为空 | summary=ok |

---

# 二、测试执行说明

## 1️⃣ 准备测试环境

1. 下载单体测试脚本：

```bash
curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/check_gitlab_names_json_UnitTest.sh \
  -o check_gitlab_names_json_UnitTest.sh
```

2. 赋予执行权限：

```bash
chmod +x check_gitlab_names_json_UnitTest.sh
```

---

## 2️⃣ 执行测试

```bash
./check_gitlab_names_json_UnitTest.sh
```

---

## 3️⃣ 期望控制台输出

```text
✅ PASS
✅ PASS
✅ PASS
✅ PASS
✅ PASS
✅ PASS
✅ PASS
✅ PASS
🎉 All tests passed (v3 enterprise level)
```

---

# 三、测试逻辑说明

1. **函数行为**  
   - 每个 UT 都会调用对应检测函数：
     - check_namespace  
     - check_service  
     - check_pvc  
     - check_pod  
   - 验证是否向 `json_entries` 正确 push 对应 error/warning。

2. **内部状态验证**  
   - UT-01 ~ UT-05 使用 `assert_array_contains` 验证 `json_entries` 是否包含期望值。
   - UT-06 ~ UT-08 使用 `calculate_summary` 验证 summary 返回值。

3. **断言工具**
   - `assert_equal` 验证 summary 返回值  
   - `assert_array_contains` 验证 json_entries 是否包含预期元素  
   - `assert_array_length` 验证 json_entries 长度

---

# 四、返回值说明

函数 `calculate_summary` 返回值：

```bash
error
warning
ok
```

对应关系：

| json_entries 状态 | calculate_summary 返回值 |
|-----------------|-------------------------|
| 包含 error      | error                   |
| 无 error，仅 warning | warning               |
| json_entries 为空 | ok                      |

---

# 五、异常场景说明

| 场景 | 返回行为 |
|------|----------|
| namespace/service/pvc/pod 不存在 | json_entries push 对应 error/warning，summary 返回正确 |
| json_entries 同时有 error + warning | summary 返回 error |
| json_entries 仅 warning | summary 返回 warning |
| json_entries 为空 | summary 返回 ok |

---

# 六、企业级扩展建议（可选）

1. 增加成功路径 mock，覆盖正常场景  
2. 增加 branch 覆盖测试，提升代码质量  
3. 生成 JSON 测试报告，便于 CI/CD 集成  
4. CI 自动化执行，GitHub Actions / GitLab CI 支持  
5. 扩展为多模块可复用的单体测试框架  

---

# 七、结论

- **check_gitlab_names_json.sh** 属于企业级单体测试模块  
- 可验证 Kubernetes HA 组件命名与状态  
- v3 测试覆盖行为 + 内部状态  
- 可作为 CI/CD 流水线验证环节  
- 支持扩展和统计报告生成  
