# KubeEdge 集群健康检测脚本说明

## 脚本文件
- **文件名**: `kubeedge_health_check.sh`  
  > 可固定名称运行，日志和报告带时间戳自动生成，避免重复覆盖。  

## 功能概述
- 对 KubeEdge 集群进行全面健康检测，包括：
  1. **网络健康**  
     - 控制中心网络接口状态  
     - 网络中节点扫描  
     - 核心服务端口可达性（kube-apiserver、kubelet）  
  2. **硬件健康**  
     - CPU 核心数及负载  
     - 内存总量、可用及使用率  
     - 磁盘总量、可用及使用率  
  3. **配置健康**  
     - kubeconfig 文件是否存在  
     - KUBECONFIG 环境变量  
     - 系统时区  
  4. **Kubernetes 服务状态**  
     - kubectl 能否连接集群  
     - 节点就绪状态  
     - 核心命名空间 Pod 运行状态  
     - k9s 是否安装  
  5. **边缘节点握手状态**  
     - 边缘节点数量及就绪状态  
     - 节点 KubeEdge 组件部署情况  
     - 云边通信心跳检测  
     - 网络连通性检查  

## 输出结果
- **日志文件**: 保存到 NAS，例如  
  `\\TRUENAS\Multi-Agent-Log\kubeedge_health_check_<timestamp>.log`
- **HTML 报告**: 保存到 `/tmp`，文件名带时间戳  
  例如 `/tmp/kubeedge-health-report-20260217_143005.html`  
- **报告内容**:  
  - 总检查项、通过、警告、失败统计  
  - 每项检查的状态、结果及备注  
  - 错误详情与部署建议  

## 使用方式
1. 将脚本上传到控制中心（192.168.1.10）  
2. 给脚本执行权限：
   ```bash
   chmod +x kubeedge_health_check.sh
