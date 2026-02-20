# GitLab YAML + JSON + HTML 生成脚本说明书

| 字段 | 内容 |
| :-- | :-- |
| 脚本名称 | `gitlab_yaml_gen.sh` |
| 版本 | v1.0.3 |
| 创建日期 | 2026-02-21 |

---

## 一、功能说明

`gitlab_yaml_gen.sh` 是一个用于生成 GitLab 部署相关 Kubernetes YAML 文件的自动化脚本，同时生成对应的 JSON 文件和 HTML 报告。

| 功能模块 | 说明 |
| :-- | :-- |
| 生成 Kubernetes YAML | Namespace、Secret、StatefulSet、Service（NodePort）、CronJob |
| 生成 JSON 文件 | 将 YAML 文件路径列表保存为 `yaml_list.json`，便于自动化工具调用 |
| 生成 HTML 报告 | 展示文件列表、大小、JSON 内容、生成时间及输出目录信息 |
| 日志记录 | 全量日志写入固定输出目录，包含逐行执行跟踪 |

---

## 二、输出目录结构

```
/mnt/truenas/Gitlab_yaml_output/
    ├── gb_namespace.yaml
    ├── gb_secret.yaml
    ├── gb_statefulset.yaml
    ├── gb_service.yaml
    ├── gb_cronjob.yaml
    └── yaml_list.json

/mnt/truenas/Gitlab_output/
    ├── full_script.log
    └── postgres_ha_info.html
```

| 变量 | 路径 | 内容 |
| :-- | :-- | :-- |
| `YAML_DIR` | `/mnt/truenas/Gitlab_yaml_output` | 所有 YAML 文件和 `yaml_list.json` |
| `OUTPUT_DIR` | `/mnt/truenas/Gitlab_output` | 日志和 HTML 报告 |

---

## 三、详细功能描述

### 1. YAML 文件生成

| 文件名 | 功能 | 关键配置 |
| :-- | :-- | :-- |
| `gb_namespace.yaml` | 创建 GitLab 命名空间 | `name: ns-test-gitlab` |
| `gb_secret.yaml` | GitLab root 密码 Secret | `root-password: secret123` |
| `gb_statefulset.yaml` | GitLab StatefulSet 配置 | 镜像、环境变量、VolumeClaimTemplates（50Gi） |
| `gb_service.yaml` | GitLab 服务暴露配置 | NodePort: 22/30022, 80/30080, 5005/35050 |
| `gb_cronjob.yaml` | GitLab 定时任务 | `registry-garbage-collect`，挂载 PVC |

> YAML 文件前缀固定为 `gb_`，便于统一管理和识别。

### 2. JSON 文件生成

**文件名：** `yaml_list.json`

```json
[
  "/mnt/truenas/Gitlab_yaml_output/gb_namespace.yaml",
  "/mnt/truenas/Gitlab_yaml_output/gb_secret.yaml",
  "/mnt/truenas/Gitlab_yaml_output/gb_statefulset.yaml",
  "/mnt/truenas/Gitlab_yaml_output/gb_service.yaml",
  "/mnt/truenas/Gitlab_yaml_output/gb_cronjob.yaml"
]
```

### 3. HTML 报告生成

**文件名：** `postgres_ha_info.html`

| 内容项 | 说明 |
| :-- | :-- |
| 生成时间 | 脚本执行时间戳 |
| YAML 文件目录 | 输出目录路径 |
| JSON 文件路径 | `yaml_list.json` 路径 |
| YAML 文件列表及大小 | 各文件名与字节数 |
| JSON 内容 | 可直接查看，用于可视化审查 |

### 4. 日志输出

**文件名：** `full_script.log`

| 记录内容 | 说明 |
| :-- | :-- |
| 命令执行跟踪 | 脚本逐行输出 |
| 文件生成状态 | 各文件创建结果 |
| 错误信息 | 异常捕获记录 |

---

## 四、使用方法

### 1. 运行脚本

```bash
chmod +x gitlab_yaml_gen.sh
./gitlab_yaml_gen.sh
```

### 2. 输出查看

```bash
# YAML 文件及 JSON 文件
ls -l /mnt/truenas/Gitlab_yaml_output
cat /mnt/truenas/Gitlab_yaml_output/yaml_list.json

# HTML 报告
firefox /mnt/truenas/Gitlab_output/postgres_ha_info.html

# 全量日志
tail -f /mnt/truenas/Gitlab_output/full_script.log
```

---

## 五、单元测试

```bash
chmod +x create_gitlab_yaml_UnitTest.sh
./create_gitlab_yaml_UnitTest.sh
```

| 测试项 | 说明 |
| :-- | :-- |
| YAML 文件存在 | 验证所有 YAML 文件已生成 |
| YAML 内容正确 | 校验关键字段 |
| JSON 文件生成 | 验证 `yaml_list.json` 存在 |
| HTML 报告生成 | 验证报告文件存在 |
| 全量日志写入 | 验证日志完整性 |

> 单元测试完全使用固定目录，不再依赖 `/tmp` 临时目录。

---

## 六、版本更新记录

| 版本 | 日期 | 更新内容 |
| :-- | :-- | :-- |
| v1.0.0 | — | 创建 YAML / JSON / HTML 脚本 |
| v1.0.1 | — | 修复 YAML 文件路径和 JSON 输出目录 |
| v1.0.2 | — | 增加 HTML 文件生成，日志输出优化 |
| v1.0.3 | 2026-02-21 | 固定目录化，不再依赖 `/tmp`，YAML 前缀统一为 `gb_` |

---

## 七、注意事项

| 类别 | 说明 |
| :-- | :-- |
| 固定目录依赖 | 确保 `/mnt/truenas/Gitlab_yaml_output` 和 `/mnt/truenas/Gitlab_output` 可写；边缘或非 NAS 环境可修改 `YAML_DIR` 和 `OUTPUT_DIR` |
| 依赖工具 | `bash`、`jq`（生成 JSON）、`wc`（HTML 文件大小统计） |
| 扩展性 | 模块名 `$MODULE` 可修改；YAML 生成逻辑可按需扩展 |
