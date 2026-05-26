# Gate 代理网关

<p align="center">
  <img src="https://img.shields.io/badge/version-1.3.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/core-singbox-green.svg" alt="Core">
  <img src="https://img.shields.io/badge/license-Apache%202.0-orange.svg" alt="License">
</p>

Gate 是一款**完全开源**的轻量级代理网关管理工具。

## 🌟 核心特性

- 🚀 **100% 开源**：所有源码公开，支持二开。
- 🔧 **智能向导**：内置 `gate setup` 向导，一键连接面板，无需手写配置。
- 🔄 **无缝更新**：`gate update` 支持热重载，更新后立即生效。
- 📦 **面板驱动**：基于 Xboard UniProxy API，配置自动同步。
- 🛡️ **内存监控**：自动释放内存，自动清理日志。

---

## 🚀 快速开始

### 1. 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)
```

### 2. 配置向导 (无需手动编辑文件)

安装完成后，直接输入 `gate`，系统会自动引导你输入面板地址、密钥和节点 ID。
或者手动启动向导：

```bash
gate setup
```

### 3. 常用命令

| 命令 | 功能 |
| :--- | :--- |
| `gate` | 进入交互菜单 (含配置向导) |
| `gate setup` | 启动配置向导 |
| `gate update` | 更新脚本 (自动重启) |
| `gate monitor start` | 开启内存监控 |
| `gate error` | 查看错误日志 |

## 📜 许可证

Apache License 2.0
