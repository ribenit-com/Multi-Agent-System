redis-ha-chart/        # Helm Chart 根目录（Git 仓库里的目录）
├── Chart.yaml         # Helm Chart 信息
├── values.yaml        # 默认配置
└── templates/         # Kubernetes YAML 模板
    ├── statefulset.yaml
    ├── service.yaml
    └── headless-service.yaml
