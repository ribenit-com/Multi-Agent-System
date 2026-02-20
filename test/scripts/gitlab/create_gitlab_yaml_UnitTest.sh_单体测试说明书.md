GitLab 内网边缘环境部署手册
1. 架构定位
本方案采用 GitLab Omnibus 单体容器 模式，通过 StatefulSet 保证数据一致性。专为内网 n8n 工作流同步及 KubeEdge 镜像下发设计。

2. 核心组件说明
StatefulSet (sts-gitlab): 核心应用。集成 Git 仓库、镜像仓库、数据库。

资源限制: 锁定 4Gi-8Gi 内存，防止 OOM（内存溢出）导致边缘侧同步中断。

启动探测 (startupProbe): 预留 300 秒初始化宽限，解决 GitLab 启动慢导致的 Pod 重启死循环。

Service (svc-gitlab-nodeport):

30080: Web 界面。

30022: SSH 端口（n8n 同步代码）。

35050: 镜像仓库（KubeEdge 边缘节点拉取镜像）。

CronJob (gitlab-gc-worker):

物理清理: 每周日凌晨执行，强制回收磁盘空间。这是防止磁盘爆满的核心保险。

3. 关键配置重点（稳定性）
Registry 优化: 开启逻辑清理策略，允许在 UI 界面设置标签保留规则。

性能裁剪: 限制 puma 进程数为 2，降低空闲内存占用。

边缘适配: 镜像仓库直接绑定 NodePort，规避 Ingress 代理大文件时的超时和容量限制。

4. 运维注意事项
磁盘预警: GitLab 数据目录（/var/opt/gitlab）包含数据库、Git 仓库和 Docker 镜像。当占用率超过 80% 时，需手动触发 CronJob。

不安全仓库: 边缘节点拉取镜像前，必须在本地 Docker 配置 insecure-registries。

持久化: 不要删除 PVC。如果更换节点，K8s 会通过 StatefulSet 自动重新挂载。

5. 部署命令
Bash
# 1. 部署全家桶
kubectl apply -f gitlab-pro.yaml

# 2. 查看启动进度 (GitLab 首次启动约需 3-5 分钟)
kubectl logs -f sts-gitlab-0 -n ns-gitlab

# 3. 获取初始 root 密码
# 如果 Secret 没生效，可执行：
kubectl exec -it sts-gitlab-0 -n ns-gitlab -- grep 'Password:' /etc/gitlab/initial_root_password
