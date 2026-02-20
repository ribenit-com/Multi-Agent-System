# GitLab YAML 生成脚本单体测试说明书（v1.0）

**模块**：GitLab 内网生产环境  
**类型**：YAML 生成脚本  
**性质**：功能型脚本，自动生成 Namespace、Secret、StatefulSet、Service、PVC、CronJob YAML，遵循企业级标准命名  

---

# 一、单体测试观点表

| 编号 | 函数/检测点 | 场景 | 期望 |
|------|-------------|------|------|
| UT-01 | 参数校验 | 未传入 MODULE | 输出 Usage 并 exit 1 |
| UT-02 | 参数校验 | 未传入 WORK_DIR | 使用默认 \$HOME/gitlab_scripts 并创建目录 |
| UT-03 | 目录创建 | WORK_DIR 不存在 | 自动创建 WORK_DIR |
| UT-04 | Namespace YAML | 正常执行 | 生成 `${MODULE}_namespace.yaml` 文件，内容正确 |
| UT-05 | Secret YAML | 正常执行 | 生成 `${MODULE}_secret.yaml` 文件，含 root-password |
| UT-06 | StatefulSet YAML | 正常执行 | 生成 `${MODULE}_statefulset.yaml`，含 volumeClaimTemplates 与环境变量配置 |
| UT-07 | Service YAML | 正常执行 | 生成 `${MODULE}_service.yaml`，端口与 NodePort 对应 |
| UT-08 | CronJob YAML | 正常执行 | 生成 `${MODULE}_cronjob.yaml`，含 registry GC 命令和 PVC volume |
| UT-09 | YAML 内容验证 | 所有 YAML | 文件内容格式正确，可被 `kubectl apply -f` 接受 |
| UT-10 | 输出提示 | 脚本执行完成 | 控制台输出生成文件路径与名称 |

---

# 二、测试执行说明

## 1️⃣ 准备测试环境

1. 下载或准备测试脚本：

```bash
curl -L \
  https://raw.githubusercontent.com/ribenit-com/Multi-Agent-System/main/test/scripts/gitlab/gitlab_yaml_gen_UnitTest.sh \
  -o gitlab_yaml_gen_UnitTest.sh

赋予执行权限：

chmod +x gitlab_yaml_gen_UnitTest.sh

确认测试目录不存在，或手动清理旧文件：

rm -rf $HOME/gitlab_scripts/*
2️⃣ 执行测试
./gitlab_yaml_gen_UnitTest.sh

或者传入自定义参数：

./gitlab_yaml_gen_UnitTest.sh GitLab_Test /tmp/gitlab_test ns-test-gitlab sc-fast 50Gi gitlab/gitlab-ce:15.0 gitlab.test.local 192.168.50.10 35050 30022 30080
3️⃣ 期望控制台输出
✅ GitLab YAML 已生成到 /tmp/gitlab_test
📦 Namespace: GitLab_Test_namespace.yaml
📦 Secret: GitLab_Test_secret.yaml
📦 StatefulSet + PVC: GitLab_Test_statefulset.yaml
📦 Service: GitLab_Test_service.yaml
📦 CronJob: GitLab_Test_cronjob.yaml
4️⃣ 验证 YAML 文件生成
ls -l /tmp/gitlab_test/

期望看到：

GitLab_Test_namespace.yaml
GitLab_Test_secret.yaml
GitLab_Test_statefulset.yaml
GitLab_Test_service.yaml
GitLab_Test_cronjob.yaml
5️⃣ 验证 YAML 内容

示例命令：

cat /tmp/gitlab_test/GitLab_Test_namespace.yaml

应包含：

apiVersion: v1
kind: Namespace
metadata:
  name: ns-test-gitlab

StatefulSet 文件示例验证：

grep -A3 "containers:" /tmp/gitlab_test/GitLab_Test_statefulset.yaml

应包含 GitLab 镜像、环境变量及 volumeMounts 配置。

Service 文件端口验证：

grep "nodePort" /tmp/gitlab_test/GitLab_Test_service.yaml

应包含：

nodePort: 30080
nodePort: 30022
nodePort: 35050

CronJob 文件验证：

grep "command" /tmp/gitlab_test/GitLab_Test_cronjob.yaml

应包含：

command: ["/bin/sh", "-c", "gitlab-ctl registry-garbage-collect -m"]
三、测试逻辑说明

函数行为

脚本按模块功能生成对应 YAML

Namespace、Secret、StatefulSet、Service、CronJob 都独立生成

确保 PVC 与存储类配置正确

内部状态验证

UT-01 ~ UT-03：验证参数与目录创建逻辑

UT-04 ~ UT-09：验证 YAML 文件生成及内容正确性

UT-10：验证控制台输出

断言工具

assert_file_exists 验证 YAML 文件生成

assert_file_contains 验证 YAML 内容

assert_equal 验证控制台输出信息

四、返回值说明
exit 0    # 执行成功，所有 YAML 文件生成完毕
exit 1    # 参数错误或生成失败
五、异常场景说明
场景	返回行为
未传 MODULE	输出 Usage 并 exit 1
WORK_DIR 无法创建	bash 报错退出
PVC_SIZE/StorageClass 格式错误	YAML 文件生成失败
NodePort 超出范围	YAML 文件生成但 kubectl apply 可能报错
镜像不存在	YAML 生成正常，但容器拉取失败
六、企业级扩展建议（可选）

增加 YAML 文件 Schema 校验 (kubectl apply --dry-run=client)

支持多副本配置与资源自动伸缩

增加多环境支持（dev / staging / prod）

支持外部 Secret 管理（Vault / K8s Secret）

自动生成 README 或部署文档

可集成 CI/CD 流水线，自动生成 YAML 并应用

七、结论

GitLab YAML 生成脚本属于企业级功能模块

可自动生成完整 Namespace、Secret、StatefulSet、Service、PVC、CronJob YAML

测试覆盖参数校验、文件生成、内容正确性、控制台输出

支持 CI/CD 集成和企业标准化命名规范
