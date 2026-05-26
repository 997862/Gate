# Gate 代理网关

<p align="center">
  <img src="https://img.shields.io/badge/version-1.2.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/core-singbox-green.svg" alt="Core">
  <img src="https://img.shields.io/badge/license-Apache%202.0-orange.svg" alt="License">
  <img src="https://img.shields.io/badge/Open%20Source-100%25-brightgreen.svg" alt="Open Source">
</p>

Gate 是一款**完全开源**的轻量级代理网关管理工具，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心构建。

## 🌟 核心特性

- 🚀 **100% 开源**：核心二进制与管理脚本全部开源，无加密、无混淆，支持任意二开。
- 🔧 **面板驱动**：完美适配 Xboard / V2board (UniProxy API)，配置自动同步，本地零配置。
- 🛡️ **智能监控**：内置内存监控，内存超 80% 自动重启释放，定期自动清理日志。
- 📦 **多协议**：基于 sing-box，支持 VMess/VLESS/Trojan/Shadowsocks/Hysteria2 等。

---

## 📚 文档

- [快速安装](docs/install.md)
- [配置指南](docs/config.md)
- [命令手册](docs/commands.md)
- [常见问题](docs/faq.md)

## 💻 二次开发与源码下载

本项目所有源码均为纯文本脚本，您可以直接下载修改：

1. **克隆仓库**：
   ```bash
   git clone https://github.com/997862/Gate.git
   cd Gate
   ```

2. **核心源码**：
   - 管理脚本: `gate-manager.sh`
   - 安装脚本: `install.sh`
   - 核心程序: `bin/gate-core-amd64` (sing-box 编译版)

3. **自定义安装**：
   修改 `install.sh` 中的 `GITHUB_REPO` 变量指向您的仓库地址即可。

## 📜 许可证

本项目基于 **Apache License 2.0** 开源。
