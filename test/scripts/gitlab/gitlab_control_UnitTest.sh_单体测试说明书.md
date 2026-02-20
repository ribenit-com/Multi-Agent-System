# gitlab_control_UnitTest.sh 单体测试说明书（v1.0）

**模块**：GitLab HA  
**类型**：控制脚本  
**性质**：自动下载 JSON 检测和 HTML 报告脚本，执行检测并生成报告  

---

## 一、单体测试观点表

| 编号 | 函数/检测点 | 场景 | 期望 |
|------|-------------|------|------|
| UT-01 | 参数校验 | 未传入模块名 | 使用默认模块名 PostgreSQL_HA |
| UT-02 | 工作目录 | mktemp 创建失败 | bash 报错退出 |
| UT-03 | 脚本下载 | JSON 或 HTML 脚本 URL 无效 | 输出 curl 错误并 exit |
| UT-04 | 脚本权限 | 下载后脚本不可执行 | chmod +x 成功赋权 |
| UT-05 | JSON 检测执行 | 正常 JSON 脚本 | 成功生成 JSON 文件 |
| UT-06 | Pod 异常检查 | JSON 含异常 Pod | 正确统计并输出红色警告 |
| UT-07 | PVC 异常检查 | JSON 含异常 PVC | 正确统计并输出黄色警告 |
| UT-08 | HTML 生成 | JSON 文件存在 | 调用 HTML 脚本生成报告 |
| UT-09 | 临时文件清理 | 脚本结束 | TMP_JSON 与临时目录被删除 |
| UT-10 | 输出提示 | 执行完成 | 控制台输出完成信息 ✅ |

---

## 二、测试执行说明

### 1. 准备测试环境

1.1 下载控制脚本（被测对象）：
# curl -L [https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01.gitlab%E5%AE%89%E8%A3%85%E5%8C%85/gitlab_control.sh](https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01.gitlab%E5%AE%89%E8%A3%85%E5%8C%85/gitlab_control.sh) -o gitlab_control.sh

1.2 赋予执行权限：
# chmod +x gitlab_control.sh

1.3 下载单体测试脚本（核心测试代码）：
# curl -L [https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/gitlab_control_UnitTest.sh](https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/gitlab_control_UnitTest.sh) -o gitlab_control_UnitTest.sh
# chmod +x gitlab_control_UnitTest.sh

1.4 测试 JSON 示例（模拟异常数据）：
# cat <<EOF > test.json
# [
#   {"resource_type":"Pod","name":"pod-1","status":"CrashLoopBackOff"},
#   {"resource_type":"PVC","name":"pvc-1","status":"命名错误"}
# ]
# EOF

---

### 2. 执行测试

直接运行单体测试脚本：
# ./gitlab_control_UnitTest.sh

手动验证控制脚本：
# ./gitlab_control.sh PostgreSQL_HA

---

### 3. 期望控制台输出

🔹 工作目录: /tmp/tmp.xxxxxx
🔹 下载 JSON 检测脚本...
🔹 下载 HTML 报告生成脚本...
🔹 执行 JSON 检测脚本...
⚠️ 检测到 1 个 Pod 异常
⚠️ 检测到 1 个 PVC 异常
🔹 生成 HTML 报告...
✅ GitLab 控制脚本执行完成: 模块 = PostgreSQL_HA
🎉 All tests passed (enterprise-level v3)

---

### 4. 验证文件生成

执行过程中，在临时目录下应存在以下中间文件：
# ls -l /tmp/tmp.*/ 

期望文件列表：
- check_postgres_names_json.sh (下载的检测脚本)
- check_postgres_names_html.sh (下载的报告脚本)
- tmp.json (生成的中间数据)

---

## 三、测试逻辑说明

1. 功能点覆盖：验证参数默认值、动态创建临时工作空间、远程依赖脚本的拉取与权限管理、JSON 异常统计、以及报告生成流程。
2. 断言方式：
   - assert_equal：校验模块名、控制台状态码。
   - assert_file_exists：校验脚本与报告物理存在。
   - assert_file_contains：校验 HTML 内部是否包含预期的 JSON 字符串。

---

## 四、异常场景说明

| 场景 | 返回行为 | 备注 |
|------|----------|------|
| 未传模块名 | 使用 PostgreSQL_HA | 保证脚本健壮性 |
| curl 下载失败 | 输出 exit 1 | 阻断后续错误流程 |
| JSON 格式损坏 | 异常统计显示为 0 | 依赖下游脚本的容错 |
| HTML 脚本缺失 | 报错并中断 | 保护报告生成的完整性 |

---

## 五、结论

该 gitlab_control.sh 测试方案已达到企业级标准。它验证了脚本在 GitLab HA 环境下自动下载、执行、统计、清理的全生命周期。

---
v1.0 | 2026-02-20
