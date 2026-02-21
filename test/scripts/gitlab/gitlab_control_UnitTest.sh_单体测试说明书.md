全套代码

https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/check_gitlab_names_html.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/check_gitlab_names_json.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/create_gitlab_yaml.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/deploy_gitlab_to_argocd_.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/scripts/01gitlab/gitlab_control.sh

https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/check_gitlab_names_html_UnitTest.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/check_gitlab_names_json_UnitTest.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/create_gitlab_yaml_UnitTest.sh
https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/gitlab_control_UnitTest.sh


# GitLab HA 控制脚本 单体测试说明书

| 字段 | 内容 |
| :-- | :-- |
| 版本 | v1.1 |
| 更新日期 | 2026-02-20 |
| 模块 | GitLab HA |
| 类型 | 控制脚本 |
| 测试性质 | 自动下载检测脚本、执行巡检、生成 HTML 报告 |

---

## 一、测试范围与观点表

| 编号 | 函数/检测点 | 场景描述 | 期望结果 |
| :-- | :-- | :-- | :-- |
| UT-01 | 参数校验 | 未传入模块名 | 自动使用默认模块名 `PostgreSQL_HA` |
| UT-02 | 工作目录创建 | `mktemp` 创建失败 | Bash 报错并退出 |
| UT-03 | 依赖脚本下载 | JSON 或 HTML 脚本 URL 无效 | 输出 curl 错误信息并 `exit` |
| UT-04 | 脚本权限设置 | 下载后的脚本不可执行 | `chmod +x` 成功赋权 |
| UT-05 | JSON 检测执行 | JSON 检测脚本运行正常 | 成功生成 `.json` 中间文件 |
| UT-06 | Pod 异常统计 | JSON 数据中包含异常 Pod | 正确统计异常 Pod 数量并输出红色警告 |
| UT-07 | PVC 异常统计 | JSON 数据中包含异常 PVC | 正确统计异常 PVC 数量并输出黄色警告 |
| UT-08 | HTML 报告生成 | JSON 中间文件存在 | 调用 HTML 脚本生成最终报告 |
| UT-09 | 临时文件清理 | 脚本执行结束 | `TMP_JSON` 与临时工作目录被删除 |
| UT-10 | 终端输出提示 | 执行完成 | 控制台输出完成信息与最终结果 |
| UT-11 | `check_gitlab_names_json_UnitTest.sh` | 单体测试脚本自验证 | JSON 检测逻辑正确，输出统计汇总 |

---

## 二、测试执行指南

### 1. 环境准备

#### 1.1 下载 JSON 单体测试脚本

```bash
curl -L "https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/refs/heads/main/test/scripts/gitlab/gitlab_control_UnitTest.sh" \
  -o gitlab_control_UnitTest.sh
chmod +x gitlab_control_UnitTest.sh
```

#### 1.2 准备模拟 JSON 数据

```bash
cat <<EOF > test.json
[
  {"resource_type":"Pod", "name":"pod-1", "status":"CrashLoopBackOff"},
  {"resource_type":"PVC", "name":"pvc-1", "status":"命名错误"}
]
EOF
```

### 2. 执行测试

#### 2.1 运行主控制脚本单体测试

```bash
./gitlab_control_UnitTest.sh
```

#### 2.2 运行 JSON 检测单体测试

```bash
./check_gitlab_names_json_UnitTest.sh
```

#### 2.3 手动验证控制脚本（可选）

```bash
./gitlab_control.sh PostgreSQL_HA
```

### 3. 预期控制台输出

```
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

### 4. 验证中间文件生成

```bash
ls -l /tmp/tmp.*/
```

| 文件名 | 说明 |
| :-- | :-- |
| `check_postgres_names_json.sh` | 下载的 JSON 检测脚本 |
| `check_postgres_names_html.sh` | 下载的 HTML 报告脚本 |
| `check_gitlab_names_json_UnitTest.sh` | JSON 检测单体测试脚本 |
| `tmp.json` | 生成的中间 JSON 数据 |

---

## 三、测试逻辑详解

### 功能点覆盖

- 参数默认值处理
- 临时工作空间动态创建
- 远程依赖脚本拉取与权限管理
- JSON 异常统计
- HTML 报告生成
- 单体测试脚本自验证（`check_gitlab_names_json_UnitTest.sh`）

### 断言策略

| 断言方法 | 用途 |
| :-- | :-- |
| `assert_equal` | 校验模块名、命令返回值等状态码 |
| `assert_file_exists` | 确认关键脚本与报告文件已生成 |
| `assert_file_contains` | 验证 HTML 报告内容中是否包含预期的 JSON 数据结构 |

---

## 四、异常场景与容错机制

| 异常场景 | 脚本行为 | 说明 |
| :-- | :-- | :-- |
| 未传递模块名 | 默认使用 `PostgreSQL_HA` | 提升脚本健壮性 |
| curl 下载依赖失败 | 输出错误信息并 `exit 1` | 阻断后续流程，避免连环错误 |
| JSON 数据格式损坏 | 异常统计结果显示为 0 | 依赖下游脚本的容错能力 |
| HTML 生成脚本缺失 | 报错并中断执行 | 保证报告生成的完整性，避免空跑 |
| 单体测试脚本异常 | 输出错误并终止 UT | 确保 `check_gitlab_names_json_UnitTest.sh` 验证正确 |

---

## 五、结论

本测试方案对 `gitlab_control.sh` 在 GitLab HA 环境下的自动下载、异常检测、统计聚合、报告生成及资源清理的全流程进行了全面验证。新增 `check_gitlab_names_json_UnitTest.sh` 使 JSON 检测逻辑可自验证，覆盖正常路径与关键异常路径，符合企业级脚本交付标准，确保脚本在生产部署中的可靠性与可观测性。

---

*文档结束 — v1.1 | 2026-02-20*
