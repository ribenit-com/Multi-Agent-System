# create_storageclass_sc-ssd-high.sh 系统简要说明

## 脚本名称
`create_storageclass_sc-ssd-high.sh`

## 功能
- 创建一个固定命名规则的 Kubernetes StorageClass：`sc-ssd-high`  
- 支持配置以下参数：
  - **Provisioner**：存储提供器（默认 `kubernetes.io/no-provisioner`，可用于本地 PV 或云存储）  
  - **ReclaimPolicy**：回收策略（`Retain` 或 `Delete`）  
  - **VolumeBindingMode**：卷绑定模式（`Immediate` 或 `WaitForFirstConsumer`）  

## 使用说明
1. **创建本地 PV 类型 StorageClass（测试环境）**：
```bash
./create_storageclass_sc-ssd-high.sh kubernetes.io/no-provisioner Retain
```

2. **创建云存储类型 StorageClass（生产环境）**：
```bash
./create_storageclass_sc-ssd-high.sh rook-ceph.rbd.csi.ceph.com Delete WaitForFirstConsumer
```

## 脚本执行逻辑
1. 固定 StorageClass 名称为 `sc-ssd-high`  
2. 读取可选参数（Provisioner、ReclaimPolicy、VolumeBindingMode）  
3. 检查 StorageClass 是否已存在：
   - 已存在 → 提示跳过  
   - 不存在 → 生成 YAML 并通过 `kubectl apply` 创建  
4. 输出创建完成提示  

## 特点
- **命名规范统一**：固定为 `sc-ssd-high`，便于和 PostgreSQL HA GitOps YAML 配合使用  
- **安全可靠**：避免手动创建本地 PV 目录导致的权限问题  
- **可扩展**：可修改参数以适应不同存储环境（本地/云存储）  
- **自动化部署**：可集成在 PostgreSQL HA 自动执行脚本中，一键完成 StorageClass 创建
