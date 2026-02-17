
## 📊 目录说明

| 目录 | 用途 | 重要性 |
|------|------|--------|
| `deploy/` | 所有部署脚本，按服务分类 | ⭐⭐⭐⭐⭐ |
| `docs/` | 完整文档体系，从入门到精通 | ⭐⭐⭐⭐⭐ |
| `scripts/` | 日常运维辅助脚本 | ⭐⭐⭐⭐ |
| `tests/` | 确保代码质量 | ⭐⭐⭐ |
| `examples/` | 帮助用户快速上手 | ⭐⭐⭐ |
| `.github/` | 社区协作规范 | ⭐⭐ |

## 🎯 核心文件说明

### 根目录文件
| 文件 | 作用 |
|------|------|
| `README.md` | 项目总入口，快速了解项目 |
| `LICENSE` | MIT 许可证，明确使用权限 |
| `.gitignore` | 忽略不需要版本控制的文件 |
| `SECURITY.md` | 安全漏洞报告流程 |

### deploy/ 核心脚本
| 脚本 | 位置 | 作用 |
|------|------|------|
| `install-containerd-edge.sh` | `deploy/containerd/` | 边缘节点安装 containerd |
| `deploy-n8n-stable.sh` | `deploy/n8n/` | 生产环境部署 n8n |
| `backup-n8n.sh` | `deploy/n8n/` | 定时备份 n8n 数据 |
| `utils.sh` | `deploy/common/` | 颜色定义、日志函数等工具 |

### docs/ 核心文档
| 文档 | 位置 | 作用 |
|------|------|------|
| `prerequisites.md` | `docs/installation/` | 硬件、软件要求 |
| `troubleshooting.md` | `docs/operations/` | 常见问题解决 |
| `system-design.md` | `docs/architecture/` | 系统架构设计 |
| `CHANGELOG.md` | `docs/versions/` | 完整版本历史 |

## 🔍 快速导航

```bash
# 想部署 n8n？
cd deploy/n8n/
./deploy-n8n-stable.sh

# 想看架构设计？
open docs/architecture/system-design.md

# 遇到问题？
cat docs/operations/troubleshooting.md

# 想贡献代码？
cat docs/development/contribute.md
