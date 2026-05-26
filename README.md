# Gate 代理网关

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/core-singbox-green.svg" alt="Core">
  <img src="https://img.shields.io/badge/license-Apache%202.0-orange.svg" alt="License">
  <img src="https://img.shields.io/badge/Open%20Source-100%25-brightgreen.svg" alt="Open Source">
</p>

Gate 是一款完全开源的轻量级代理网关管理工具。

**核心特性：**
- 🚀 **100% 开源**：核心管理逻辑均为标准 Bash 脚本，无加密、无混淆，欢迎审查与二开。
- 🔧 **面板驱动**：完美适配 Xboard / V2board (UniProxy API)，配置自动同步。
- 📦 **多协议**：基于 sing-box 核心，支持 VMess/VLESS/Trojan/Shadowsocks 等。
- 🚫 **零侵入**：本地不写死端口，完全听从面板指挥。

---

## 📚 文档

- [快速安装](docs/install.md)
- [配置指南](docs/config.md)
- [命令手册](docs/commands.md)
- [常见问题](docs/faq.md)

## 💻 二次开发与源码下载

本项目所有脚本均为**纯文本源码**，您可以直接下载修改：

1. **克隆仓库**：
   ```bash
   git clone https://github.com/997862/Gate.git
   cd Gate
   ```

2. **修改源码**：
   核心逻辑在 `gate-manager.sh`。您可以随意修改命令、API 路径或添加新功能。

3. **自定义安装**：
   修改 `install.sh` 中的 `GITHUB_REPO` 变量指向您的仓库地址即可。

## 📜 许可证

本项目基于 **Apache License 2.0** 开源。

## 鸣谢

- [sing-box](https://github.com/SagerNet/sing-box) — 核心引擎
- Xboard / V2board 开发者社区
