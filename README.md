Multi-Agent-System/
├── README.md                          # 项目总说明书（入口）
├── LICENSE                             # 开源许可证
├── .gitignore                          # Git 忽略文件
│
├── deploy/                             # 部署脚本目录
│   ├── README.md                       # 部署模块说明
│   ├── n8n/                            # n8n 相关脚本
│   │   ├── deploy-n8n-stable.sh        # 稳定版部署脚本（您已上传）
│   │   ├── deploy-n8n-dev.sh            # 开发测试版
│   │   ├── backup-n8n.sh                # 备份脚本
│   │   └── restore-n8n.sh               # 恢复脚本
│   ├── containerd/                      # Containerd 相关
│   │   ├── install-containerd-edge.sh   # 边缘节点安装脚本（您已上传）
│   │   └── configure-containerd.sh       # 配置脚本
│   └── common/                          # 通用函数
│       └── utils.sh                      # 颜色定义、日志函数等
│
├── docs/                                # 详细文档目录
│   ├── README.md                        # 文档索引
│   ├── installation/                     # 安装指南
│   │   ├── prerequisites.md              # 前置要求
│   │   ├── control-center.md             # 控制中心配置
│   │   └── edge-node.md                  # 边缘节点配置
│   ├── operations/                       # 运维指南
│   │   ├── daily-check.md                # 日常检查
│   │   ├── backup-restore.md             # 备份恢复
│   │   └── troubleshooting.md            # 故障排查
│   ├── architecture/                     # 架构文档
│   │   ├── system-design.md              # 系统设计
│   │   ├── network-topology.md           # 网络拓扑
│   │   └── images/                       # 架构图
│   │       ├── architecture.png
│   │       └── data-flow.png
│   └── versions/                         # 版本记录
│       └── CHANGELOG.md                   # 更新日志
│
├── examples/                             # 示例配置
│   ├── n8n-workflows/                     # n8n 工作流示例
│   └── config-examples/                   # 配置示例
│
├── scripts/                              # 辅助脚本
│   ├── check-health.sh                    # 健康检查
│   ├── monitor-logs.sh                    # 日志监控
│   └── alert.sh                           # 告警脚本
│
└── tests/                                # 测试脚本
    ├── test-deploy.sh                     # 部署测试
    └── test-connection.sh                  # 连接测试
