# check_gitlab_names_json.sh 单体测试观点表

| 编号 | 函数 | 场景 | 期望 |
|------|------|------|------|
| UT-01 | check_namespace | namespace 不存在 | error |
| UT-02 | check_namespace | enforce 模式 | warning |
| UT-03 | check_service | service 不存在 | error |
| UT-04 | check_pvc | pvc 命名不规范 | warning |
| UT-05 | check_pod | pod 非 Running | error |
| UT-06 | calculate_summary | 有 error | error |
| UT-07 | calculate_summary | 仅 warning | warning |
| UT-08 | calculate_summary | 无异常 | ok |


# GitLab HA 单体测试执行说明

## 1️⃣ 如何执行

```bash
chmod +x gitlab_ha_full_deploy_UnitTest.sh
./gitlab_ha_full_deploy_UnitTest.sh
```

---

## 2️⃣ 执行了哪些函数

测试文件通过：

```bash
source ./check_gitlab_names_json.sh
```

加载并执行以下函数：

- check_namespace
- calculate_summary

---

## 3️⃣ 返回结果是什么

正常情况下输出：

```text
✅ PASS
✅ PASS
✅ PASS
🎉 All tests passed
```

对应汇总返回值：

| 场景 | calculate_summary 返回值 |
|------|--------------------------|
| namespace 不存在 | error |
| 全部 warning | warning |
| 无异常 | ok |
