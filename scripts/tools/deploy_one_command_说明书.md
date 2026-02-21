自动下载最新脚本（你仓库里的 ArgoCD 部署脚本）
配置 GitLab 仓库凭证（用户名 + PAT）
创建/更新 ArgoCD Application
等待同步完成，Pod Ready
无需手动改 URL 或 PAT，安全执行



argocd login 192.168.1.10:30100 --username admin --password 'jiahong565' --insecure
argocd login 192.168.1.10:30100 --username admin --password jiahong565 --insecure

