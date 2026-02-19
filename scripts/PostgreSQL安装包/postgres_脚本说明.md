# PostgreSQL HA 企业级清理与规范化 PVC 初始化脚本说明

## 脚本概述

**脚本名称**: `cleanup_init_postgresql_enterprise.sh`  
**功能**: 自动清理 Kubernetes 中的 PostgreSQL HA 相关资源，并初始化规范化 PVC  
**版本**: 1.0.0 (增强版)  
**作者**: 自动化运维团队  
**更新时间**: 2026-02-19  

---

## 功能特点

1. **HA 副本自动同步**  
   - 如果 StatefulSet 已存在，自动读取 `spec.replicas`，无需手动配置 `HA_REPLICAS`。  

2. **StatefulSet 活动检测**  
   - 删除前检测 Pod 是否在运行  
   - 提示备份或快照，保证生产安全  

3. **PVC 清理与规范化**  
   - 保留命名规范的 PVC：`pvc-pg-data-0`、`pvc-pg-data-1` …  
   - 超出副本数或不符合命名规范的 PVC 会被删除  

4. **Dry-Run 模式**  
   - 默认启用 (`DRY_RUN=true`)，仅预览操作，不写入资源  
   - 可通过 `DRY_RUN=false` 执行实际操作  

5. **StorageClass 自动绑定**  
   - PVC 创建时自动绑定指定高性能存储，例如 `sc-ssd-high`  

6. **孤儿 PV 清理**  
   - 自动检测 Released 状态的 PV  
   - 仅删除属于当前 Namespace 的孤儿 PV  

7. **日志文件记录**  
   - 所有操作记录到 `postgres_cleanup_YYYYMMDD_HHMM.log`  
   - 便于审计与回溯  

---

## 使用说明

### 默认执行（Dry-Run）

```bash
bash cleanup_init_postgresql_enterprise.sh
