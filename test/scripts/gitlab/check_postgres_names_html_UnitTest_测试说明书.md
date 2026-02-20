# check_postgres_names_html.sh 单体测试说明书

版本：v2.0  
模块：PostgreSQL_HA  
类型：HTML 报告生成模块  
性质：展示型脚本（无业务判断逻辑）

---

# 一、单体测试观点表

| 编号 | 检测点 | 场景 | 期望 |
|------|--------|------|------|
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

## 1️⃣ 准备测试 JSON 文件

```bash
cat <<EOF > test.json
{
  "namespace": "ns-postgres-ha",
  "statefulset": "sts-postgres-ha",
  "status": "ok"
}
EOF
```

---

## 2️⃣ 执行测试脚本

```bash
./check_postgres_names_html.sh "PostgreSQL_HA" test.json
```

---

## 3️⃣ 期望控制台输出

```text
✅ HTML 报告生成完成: /mnt/truenas/PostgreSQL安装报告书/PostgreSQL_HA_命名规约检测报告_YYYYMMDD_HHMMSS.html
🔗 最新报告链接: /mnt/truenas/PostgreSQL安装报告书/latest.html
```

---

## 4️⃣ 验证文件生成

```bash
ls -l /mnt/truenas/PostgreSQL安装报告书/
```

期望看到：

```text
PostgreSQL_HA_命名规约检测报告_时间戳.html
latest.html -> PostgreSQL_HA_命名规约检测报告_时间戳.html
```

---

## 5️⃣ 验证 HTML 内容

```bash
cat /mnt/truenas/PostgreSQL安装报告书/latest.html
```

应包含：

```html
<h1>PostgreSQL_HA 命名规约检测报告</h1>
<pre>{
  "namespace": "ns-postgres-ha"
...
</pre>
```

---

# 三、特殊字符转义测试

## 构造包含特殊字符的 JSON

```bash
cat <<EOF > test_escape.json
{
  "value": "<error & warning>"
}
EOF
```

## 执行脚本

```bash
./check_postgres_names_html.sh "PostgreSQL_HA" test_escape.json
```

## 期望 HTML 内容显示为

```html
&lt;error &amp; warning&gt;
```

---

# 四、返回值说明

该脚本属于展示型模块：

- 不解析 JSON
- 不进行 error/warning 业务判断
- 仅负责生成 HTML 报告

---

# 五、异常场景说明

| 场景 | 返回行为 |
|------|----------|
| 参数错误 | 输出 Usage 并 exit 1 |
| JSON 文件不存在 | 输出 Usage 并 exit 1 |
| 输出目录无法创建 | bash 报错退出 |
| 正常执行 | 生成 HTML 并输出路径 |

---

# 六、企业级扩展建议（可选）

可增强为：

1. 增加 jq 校验 JSON 格式
2. 根据 error / warning 渲染不同颜色
3. 添加统计摘要区块
4. 添加报告版本号
5. 支持企业 CSS 模板
6. 支持 CI 自动归档

---

# 七、结论

check_postgres_names_html.sh 属于：

- 纯展示层
- 与 JSON 生成模块解耦
- 可作为企业级自动化交付报告模块
- 适合集成到主控脚本流水线
- 可用于 CI/CD 交付物生成
