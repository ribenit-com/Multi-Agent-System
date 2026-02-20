# gitlab_control_UnitTest.sh 单体测试说明书（v1.0）

**模块**：GitLab HA  
**类型**：控制脚本  
**性质**：自动下载 JSON 检测和 HTML 报告脚本，执行检测并生成报告  

---

# 一、单体测试观点表

| 编号 | 函数/检测点 | 场景 | 期望 |
|------|-------------|------|------|
| UT-01 | 参数校验 | 未传入模块名 | 使用默认模块名 `PostgreSQL_HA` |
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

# 二、测试执行说明

## 1️⃣ 准备测试环境

1. 下载控制脚本（被测对象）：

```bash
curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01.gitlab安装包/gitlab_control.sh \
  -o gitlab_control.sh
```

2. 赋予执行权限：

```bash
chmod +x gitlab_control.sh
```

3. 下载单体测试脚本：

```bash
curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/gitlab_control_UnitTest.sh \
  -o gitlab_control_UnitTest.sh
```

4. 测试 JSON 示例（可模拟 Pod/PVC 异常）：

```bash
cat <<EOF > test.json
[
  {"resource_type":"Pod","name":"pod-1","status":"CrashLoopBackOff"},
  {"resource_type":"PVC","name":"pvc-1","status":"命名错误"}
]
EOF
```

---

## 2️⃣ 执行测试

```bash
./gitlab_control.sh PostgreSQL_HA
```

或者直接运行单体测试：

```bash
./gitlab_control_UnitTest.sh
```

---

## 3️⃣ 期望控制台输出

```text
🔹 工作目录: /tmp/tmp.xxxxxx
🔹 下载 JSON 检测脚本...
🔹 下载 HTML 报告生成脚本...
🔹 执行 JSON 检测脚本...
⚠️ 检测到 1 个 Pod 异常
⚠️ 检测到 1 个 PVC 异常
🔹 生成 HTML 报告...
✅ GitLab 控制脚本执行完成: 模块 = PostgreSQL_HA
🎉 All tests passed (enterprise-level v3)
```

---

## 4️⃣ 验证文件生成

```bash
ls -l /tmp/tmp.xxxxxx/
```

期望看到：

```text
check_postgres_names_json.sh
check_postgres_names_html.sh
tmp.json
```

HTML 报告会根据 HTML 脚本逻辑生成在默认位置，可检查：

```bash
cat /path/to/generated_report.html
```

---

## 5️⃣ 验证 HTML 内容

```html
<h1>PostgreSQL_HA 命名规约检测报告</h1>
<pre>[
  {"resource_type":"Pod","name":"pod-1","status":"CrashLoopBackOff"},
  {"resource_type":"PVC","name":"pvc-1","status":"命名错误"}
]</pre>
```

> JSON 内容应完整显示，特殊字符 `< > &` 应被 HTML 实体转义  

---

# 三、测试逻辑说明

1. **功能点覆盖**  
   - 参数默认值  
   - 临时目录创建  
   - 下载远程脚本  
   - JSON 执行及异常统计  
   - HTML 报告生成  
   - 临时文件清理  

2. **断言方式**  
   - `assert_equal`：模块名默认值、控制台输出  
   - `assert_file_exists`：HTML 报告、脚本文件  
   - `assert_file_contains`：HTML 内容是否正确显示 JSON  

---

# 四、返回值说明

该控制脚本的返回值：

```bash
exit 0    # 执行成功
exit 1    # 参数错误或下载/执行失败
```

- 仅控制流程  
- 不解析 JSON 业务逻辑  
- 生成 HTML 报告作为输出  

---

# 五、异常场景说明

| 场景 | 返回行为 |
|------|----------|
| 未传模块名 | 使用默认模块名 `PostgreSQL_HA` |
| 工作目录创建失败 | bash 报错退出 |
| curl 下载失败 | 输出错误信息并 exit 1 |
| JSON 文件异常 | Pod/PVC 异常统计输出到控制台 |
| HTML 脚本执行失败 | bash 报错退出 |
| 临时文件删除失败 | 不影响整体流程，脚本结束 |

---

# 六、企业级扩展建议（可选）

1. 支持多个模块同时检测  
2. 支持 YAML/GitOps 自动生成  
3. 集成 CI/CD Job，自动归档 HTML 报告  
4. 报告加入版本号和时间戳  
5. 支持错误/警告高亮统计  
6. 支持自定义报告输出目录  

---

# 七、结论

- **gitlab_control.sh** 属于企业级控制脚本  
- 自动完成脚本下载、JSON 检测、异常统计、HTML 报告生成  
- 可集成到 CI/CD 流水线，支持企业自动化交付  
- v1.0 测试覆盖参数校验、异常统计、报告生成与文件清理
