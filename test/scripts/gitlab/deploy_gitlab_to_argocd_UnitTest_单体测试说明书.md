# deploy_argocd_app.sh 单体测试说明书（v1.0）

- **模块**：ArgoCD Deployment
- **类型**：自动化部署脚本
- **性质**：创建或更新 ArgoCD Application 并等待同步完成

---

## 一、单体测试观点表

| 编号 | 函数/检测点 | 场景 | 期望 |
|------|------------|------|------|
| UT-01 | 参数校验 | 未传入 ARGO_APP | 输出默认值或 Usage 并继续 |
| UT-02 | 参数校验 | 未传入 GITHUB_REPO | 输出默认值或 Usage 并 exit 1 |
| UT-03 | ArgoCD 环境检查 | ArgoCD namespace 不存在 | 输出错误并 exit 1 |
| UT-04 | ArgoCD 环境检查 | ArgoCD server 未运行 | 输出错误并 exit 1 |
| UT-05 | Application 创建/更新 | Application 不存在 | 成功创建 Application |
| UT-06 | Application 创建/更新 | Application 已存在 | 成功更新 Application，保留原配置未覆盖意外字段 |
| UT-07 | 同步等待 | Application 状态逐步 Synced/Healthy | 最终输出同步成功并 exit 0 |
| UT-08 | 同步失败 | Application 健康状态 Degraded | 输出错误信息 + YAML 并 exit 1 |
| UT-09 | 同步超时 | 超过 TIMEOUT | 输出超时信息 + YAML 并 exit 1 |
| UT-10 | 日志输出 | 执行任意步骤 | 控制台输出正确 INFO/WARN/ERROR 日志 |

---

## 二、测试执行说明

### 1️⃣ 准备测试环境

下载单体测试脚本：

```bash
curl -L \
  https://raw.githubusercontent.com/your-org/your-repo/main/test/scripts/deploy/deploy_argocd_app_UnitTest.sh \
  -o deploy_argocd_app_UnitTest.sh
```

赋予执行权限：

```bash
chmod +x deploy_argocd_app_UnitTest.sh
```

准备 Kubernetes 测试环境：确保有一个 ArgoCD namespace，确保 ArgoCD server 部署完成，可使用 `kind` 或 `minikube` 创建临时集群。

配置测试变量：

```bash
export ARGO_APP="test-postgres-ha"
export GITHUB_REPO="test-org/test-repo"
export CHART_PATH="charts/postgres-ha"
export VALUES_FILE="values.yaml"
export NAMESPACE="test-postgres"
export ARGO_NAMESPACE="argocd"
export TIMEOUT=60
```

### 2️⃣ 执行测试

```bash
./deploy_argocd_app_UnitTest.sh
```

测试脚本内部会：检查 ArgoCD namespace 和 server，创建或更新 Application，等待同步完成，输出日志和同步结果。

### 3️⃣ 期望控制台输出

**正常场景：**

```
[YYYY-MM-DD HH:MM:SS] INFO  - 检查 ArgoCD 是否存在...
[YYYY-MM-DD HH:MM:SS] INFO  - ArgoCD 环境正常
[YYYY-MM-DD HH:MM:SS] INFO  - 创建 / 更新 ArgoCD Application: test-postgres-ha
[YYYY-MM-DD HH:MM:SS] INFO  - Application 已提交给 ArgoCD
[YYYY-MM-DD HH:MM:SS] INFO  - 开始等待 ArgoCD 同步完成 (timeout=60s)
[YYYY-MM-DD HH:MM:SS] INFO  - 进度: 5/60s | sync=Synced | health=Healthy | revision=abc123
[YYYY-MM-DD HH:MM:SS] INFO  - ArgoCD Application 同步成功
✅ PASS: Application 创建/更新并同步成功
```

**失败或异常场景：**

```
[YYYY-MM-DD HH:MM:SS] ERROR - ArgoCD namespace 'argocd' 不存在
❌ FAIL: Namespace 检查失败
[YYYY-MM-DD HH:MM:SS] ERROR - Application 状态异常 (Degraded)
❌ FAIL: Application 同步失败
[YYYY-MM-DD HH:MM:SS] ERROR - ArgoCD 同步超时 (60s)
❌ FAIL: Application 同步超时
```

### 4️⃣ 验证资源生成

```bash
kubectl -n argocd get app test-postgres-ha -o yaml
```

应包含：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test-postgres-ha
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/test-org/test-repo.git
    targetRevision: main
    path: charts/postgres-ha
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: test-postgres
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

> 注意：状态信息如 `sync` 和 `health` 会根据集群实际情况显示。

---

## 三、测试逻辑说明

**函数行为**

- **参数校验**：未传入变量时使用默认值或提示
- **ArgoCD 环境检查**：namespace / server 是否存在
- **Application 创建或更新**：正确生成 YAML 并提交
- **同步等待**：轮询 sync / health 状态
- **超时或 Degraded**：打印 YAML 并 exit 1

**内部状态验证**：使用 `kubectl get ns` / `get deploy` / `get app` 检查资源是否存在，检查 Application 同步状态与健康状态。

**断言工具**

| 断言函数 | 用途 |
|---------|------|
| `assert_equal` | 验证 exit code |
| `assert_k8s_resource_exists` | 验证资源创建 |
| `assert_status` | 验证 sync/health 状态 |

---

## 四、返回值说明

| 返回值 | 说明 |
|--------|------|
| `exit 0` | Application 创建/更新并同步成功 |
| `exit 1` | 参数错误 / 环境异常 / 同步失败 / 超时 |

---

## 五、异常场景说明

| 场景 | 返回行为 |
|------|---------|
| ARGO_NAMESPACE 不存在 | 输出错误并 exit 1 |
| ArgoCD server 未运行 | 输出错误并 exit 1 |
| Application 健康状态 Degraded | 输出错误信息 + YAML 并 exit 1 |
| 同步超时 | 输出超时信息 + YAML 并 exit 1 |
| 参数缺失 | 使用默认值或输出 Usage 并 exit 1 |

---

## 六、企业级扩展建议（可选）

- 增加 `--dry-run` 模式
- 增加多环境（dev/staging/prod）支持
- 支持自定义 syncPolicy
- 输出 JSON / Markdown 同步报告
- CI/CD 集成：GitHub Actions / GitLab CI 自动执行
- 异常报警：邮件 / Slack 通知同步失败
- 日志归档与审计功能

---

## 七、结论

`deploy_argocd_app.sh` 属于企业级 ArgoCD 自动化部署脚本，可重复创建/更新 Application，支持同步状态轮询和异常检测，可集成 CI/CD 流水线。单体测试覆盖参数校验、环境检查、Application 操作、同步状态和异常处理。
