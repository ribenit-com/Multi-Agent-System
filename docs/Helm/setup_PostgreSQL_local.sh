脚本整体作用

这个脚本的目标是：

一键在 Kubernetes 集群上生成 PostgreSQL HA 部署，并通过 Helm Chart + ArgoCD 管理，同时处理 PVC/PV 问题，避免冲突。

核心流程可以分为 九步：

步骤概要
Step 0：清理已有冲突 PVC/PV
kubectl get pvc -n $NAMESPACE -l app=$APP_LABEL -o name | xargs -r kubectl delete -n $NAMESPACE
kubectl get pv -o name | grep postgres-pv- | xargs -r kubectl delete


先删除同名的 PVC（PersistentVolumeClaim）和 PV（PersistentVolume）

目的：避免之前生成的资源阻塞 Pod 调度（Pending 状态）

Step 1：检测集群 StorageClass
SC_NAME=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' || true)


检查集群里有没有 StorageClass（存储类型）

如果没有，就后面创建 hostPath PV，保证 Pod 可以使用存储

Step 2：创建 Helm Chart 目录
mkdir -p "$CHART_DIR/templates"


为 Helm Chart 准备目录结构

Helm 需要有 Chart.yaml、values.yaml、templates/

Step 3：生成 Chart.yaml
apiVersion: v2
name: postgres-ha-chart
...


描述 Helm Chart 的基础信息：名字、版本、应用版本

这是 Helm 的必备文件

Step 4：生成 values.yaml
replicaCount: 2
image:
  repository: library/postgres
persistence:
  size: 10Gi
  storageClass: ...


配置应用的变量：

副本数 (replicaCount)

镜像、用户名密码、数据库名

存储大小、StorageClass

资源限制（CPU/内存）

Helm 模板会根据这个文件生成 Kubernetes YAML

Step 5：生成 StatefulSet 模板
kind: StatefulSet
metadata:
  name: postgres
spec:
  replicas: {{ .Values.replicaCount }}
...
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      resources:
        requests:
          storage: {{ .Values.persistence.size }}
      storageClassName: {{ .Values.persistence.storageClass }}


定义 PostgreSQL 的 StatefulSet（有序部署的 Pod）

每个 Pod 都有自己的 PVC

支持 HA（多副本、持久化存储）

Step 6 & 7：生成 Service & Headless Service
kind: Service
metadata:
  name: postgres
...


postgres Service：集群内访问 PostgreSQL 的入口

postgres-headless Service：用于 StatefulSet 内部 Pod 通信（HA replication）

Step 8：如果没有 StorageClass，创建手动 PV
for i in $(seq 0 1); do
  mkdir -p /mnt/data/postgres-$i
  kubectl apply -f /tmp/postgres-pv-$i.yaml
done


如果集群没有默认 StorageClass，就用 hostPath 创建 PV

每个副本对应一个 PV，保证 Pod 可以挂载存储

Step 9：创建 ArgoCD Application
kind: Application
metadata:
  name: postgres-ha
spec:
  source:
    repoURL: ...
    path: postgres-ha-chart
    helm:
      valueFiles:
        - values.yaml
  destination:
    namespace: database
  syncPolicy:
    automated:
      prune: true
      selfHeal: true


ArgoCD 会自动从 Git 仓库拉取 Helm Chart

自动在 Kubernetes 上部署 PostgreSQL HA

selfHeal + prune 保证资源健康和同步

最终效果

Helm Chart 已生成并上传 Git

ArgoCD 监听 Git 仓库并部署 PostgreSQL HA

PVC / PV 自动处理，无冲突

Pod / Service / StatefulSet 都健康运行

💡 核心原理总结：

清理冲突 → 保证 PVC/PV 不阻塞部署

生成 Helm Chart → 把配置、模板统一管理

创建 PV（如果没有 StorageClass） → 确保持久化存储可用

ArgoCD 自动化 → GitOps 模式，持续同步 Kubernetes 资源
