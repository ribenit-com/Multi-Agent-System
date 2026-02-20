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
