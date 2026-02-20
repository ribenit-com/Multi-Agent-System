# check_gitlab_names_html.sh 单体测试说明书（v3.0）

**模块**：GitLab HA  
**类型**：HTML 报告生成  
**性质**：展示型脚本，生成 HTML 报告，不做业务判断  

---

# 一、单体测试观点表

| 编号 | 函数/检测点 | 场景 | 期望 |
|------|-------------|------|------|
| UT-01 | 参数校验 | 未传入模块名 | 输出 Usage 并 exit 1 |
| UT-02 | 参数校验 | 未传入 JSON 文件 | 输出 Usage 并 exit 1 |
| UT-03 | 参数校验 | JSON 文件不存在 | 输出 Usage 并 exit 1 |
| UT-04 | 目录创建 | 输出目录不存在 | 自动创建目录 |
| UT-05 | HTML生成 | JSON 正常 | 成功生成 HTML |
| UT-06 | HTML转义 | JSON 含 `< > &` | 正确转义为 HTML 实体 |
| UT-07 | latest 软链接 | 已存在旧 latest.html | 正确覆盖为最新报告 |
| UT-08 | 输出提示 | 执行成功 | 输出成功路径与最新链接 |

---

# 二、测试执行说明

## 1️⃣ 准备测试环境

1. 下载单体测试脚本：

    ```bash
    curl -L \
      https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/check_gitlab_names_html_UnitTest.sh \
      -o check_gitlab_names_html_UnitTest.sh
    ```

2. 赋予执行权限：

    ```bash
    chmod +x check_gitlab_names_html_UnitTest.sh
    ```

3. 准备测试 JSON 文件：

    ```bash
    cat <<EOF > test.json
    {
      "namespace": "ns-gitlab-ha",
      "statefulset": "sts-gitlab-ha",
      "status": "ok"
    }
    EOF
    ```

---

## 2️⃣ 执行测试

    ```bash
    ./check_gitlab_names_html_UnitTest.sh
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

## 4️⃣ 验证文件生成

    ```bash
    ls -l /mnt/truenas/GitLab安装报告书/
    ```

期望看到：

    ```text
    GitLab_HA_命名规约检测报告_时间戳.html
    latest.html -> GitLab_HA_命名规约检测报告_时间戳.html
    ```

---

## 5️⃣ 验证 HTML 内容

    ```bash
    cat /mnt/truenas/GitLab安装报告书/latest.html
    ```

应包含：

    ```html
    <h1>GitLab_HA 命名规约检测报告</h1>
    <pre>{
      "namespace": "ns-gitlab-ha",
      ...
    }</pre>
    ```

---

# 三、测试逻辑说明

1. **函数行为**  
   - 每个 UT 都会调用对应功能点：
     - 参数校验  
     - 输出目录创建  
     - HTML 文件生成  
     - HTML 内容转义  
   - 验证是否生成正确文件与输出路径提示。

2. **内部状态验证**  
   - UT-01 ~ UT-03 使用 `assert_equal` 验证 exit code 和输出信息  
   - UT-04 ~ UT-08 使用 `assert_file_exists` / `assert_file_contains` 验证文件和内容正确性  

3. **断言工具**  
   - `assert_equal` 验证输出和返回值  
   - `assert_file_exists` 验证 HTML 文件生成  
   - `assert_file_contains` 验证 HTML 内容是否正确  

---

# 四、返回值说明

该脚本属于展示型模块：

    ```bash
    exit 0    # 执行成功
    exit 1    # 参数错误或 JSON 文件不存在
    ```

- 不解析 JSON  
- 不进行 error/warning 业务判断  
- 仅负责生成 HTML 报告  

---

# 五、异常场景说明

| 场景 | 返回行为 |
|------|----------|
| 未传模块名 / JSON 文件不存在 | 输出 Usage 并 exit 1 |
| 输出目录无法创建 | bash 报错退出 |
| 正常执行 | 生成 HTML 并输出路径与 latest 链接 |
| JSON 含特殊字符 `< > &` | 转义为 HTML 实体 |

---

# 六、企业级扩展建议（可选）

1. 增加 JSON 格式校验（`jq`）  
2. 根据 error / warning 渲染不同颜色  
3. 添加统计摘要区块  
4. 添加报告版本号  
5. 支持企业 CSS 模板  
6. 支持 CI 自动归档  
7. 生成多模块 HTML 报告框架  

---

# 七、结论

- **check_gitlab_names_html.sh** 属于企业级展示模块  
- 与 JSON 生成模块解耦  
- 可作为企业自动化交付报告模块  
- 适合集成到主控脚本流水线  
- 支持 CI/CD 交付物生成  
- v3 测试覆盖行为 + 文件生成 + 内容校验
