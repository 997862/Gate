# 快速安装

## 一键安装

在您的 Linux 服务器 (Debian/Ubuntu/CentOS) 上运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)
```

**安装说明：**
- 脚本会自动检测架构，并从本项目 GitHub 仓库下载对应的 sing-box 核心。
- 所有源码和二进制文件均公开在仓库中，无任何隐藏依赖。

## 验证安装

安装完成后，输入 `gate -v` 查看版本。

## 开启智能维护

推荐运行以下命令开启自动维护：
```bash
gate monitor start
```
这将自动：
- 监控内存使用，超过阈值自动重启节点。
- 每天自动清理 30 天前的日志。
- 每周自动检测 GitHub 最新版本。
