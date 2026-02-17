TrueNAS 跨平台共享配置说明书 (NFS & SMB)
本手册记录了如何配置 TrueNAS CORE 以支持 Linux (NFS) 和 Windows (SMB) 客户端同时对同一数据集进行读写访问。

1. 全局协议配置
为了确保跨平台兼容性，需调整 NFS 服务端设置：

启用 NFSv4：勾选 Enable NFSv4 以支持高性能挂载。

权限模型映射：勾选 NFSv3 ownership model for NFSv4。

作用：强制 NFSv4 使用数字 UID 识别用户，避免因域名不匹配导致的权限拒绝。

2. 文件系统权限 (ACL) 设置
这是解决客户端 Permission denied 报错的核心步骤。

数据集信息
路径：/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log。

所有者 (Owner)：zdl (UID: 1001)。

所属组 (Group)：zdl。

ACL 递归应用 (关键动作)
在 Storage > Pools > Edit ACL 界面中：

设置 User 和 Group 为 zdl，并勾选 Apply User 与 Apply Group。

执行递归：拉到页面最底部，勾选 Apply permissions recursively 并 Confirm。

目的：将目录下所有由 root 创建的旧文件（如 .cshrc）权限强制刷为 zdl 拥有。

3. 共享服务配置
NFS 共享 (针对 Linux 客户端)
高级选项：设置 Mapall User 为 zdl，Mapall Group 为 zdl。

目的：解决主机 UID (1000) 与服务器 UID (1001) 不一致的问题。

SMB 共享 (针对 Windows 客户端)
共享名称：Multi-Agent-Log。

共享 ACL：设置 Everyone: Full Control。

凭据同步：若 Windows 提示密码错误，需在 TrueNAS 的 Accounts > Users 中重置 zdl 用户的密码，以同步 Samba 数据库。

4. 客户端操作指南
Linux 挂载命令
Bash
# 建议使用 NFS v3 或 v4 挂载
sudo mount -t nfs 192.168.1.6:/mnt/Agent-Ai/CSV_Data/Multi-Agent-Log /mnt/truenas
Windows 访问路径
在资源管理器输入：

Plaintext
\\192.168.1.6\Multi-Agent-Log
5. 企业级安全建议
定期快照：在 Tasks > Periodic Snapshot Tasks 开启自动快照，预防误删。

最小权限原则：系统稳定后，将 SMB 的 Everyone 权限替换为特定的用户组。

说明书版本：1.0

适用系统：TrueNAS CORE 13.0+
