# 快速安装

## 一键安装

在您的 Linux 服务器 (Debian/Ubuntu/CentOS) 上运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)
```

安装过程会自动检测架构、下载 sing-box 核心并配置 systemd 服务。

## 验证安装

安装完成后，输入 `gate -v` 查看版本。

## 自定义安装

如果您想使用修改过的版本，可以编辑 `install.sh`：
1. 修改 `SCRIPT_URL` 为您的脚本直链。
2. 修改 `CORE_BIN_URL` (可选，如果更换了 sing-box 版本)。
