# Gate 代理网关

<p align="center">
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/core-singbox-green.svg" alt="Core">
  <img src="https://img.shields.io/badge/license-Apache%202.0-orange.svg" alt="License">
</p>

Gate 是一款轻量级代理网关管理工具，基于 [sing-box](https://github.com/SagerNet/sing-box) 核心构建，提供简洁的命令行界面和多节点管理能力。

## 特性

- 🚀 **一键安装** — 单行命令完成核心下载与配置
- 📦 **多协议支持** — VMess / VLESS / Trojan / Shadowsocks / Hysteria2 / TUIC
- 🔄 **多实例管理** — systemd 驱动的节点隔离启停
- 🔧 **面板对接** — 兼容 Xboard / V2board 等主流面板
- 📝 **配置生成** — 自动生成带中文注释的节点配置
- 🗑️ **完整卸载** — 一键清除所有配置与服务

## 安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)
```

## 快速使用

```bash
# 启动交互式面板
gate

# 常用命令
gate start        # 启动节点
gate restart      # 重启节点
gate status       # 查看状态
gate log          # 实时日志
gate test         # 测试面板对接
gate update       # 更新脚本
gate uninstall    # 完全卸载
```

## 配置文件

安装后配置文件位于 `/etc/gate/gate.conf`：

```ini
type=xboard          # 面板类型
server_type=vmess    # 节点协议
node_id=1            # 节点编号
api=webapi           # 对接模式

webapi_url=          # 面板地址
webapi_key=          # 通信密钥
```

## 目录结构

```
/etc/gate/
├── gate.conf          # 主配置文件
└── <node_id>.json     # 节点运行时配置 (自动生成)

/usr/bin/gate          # 管理脚本
/usr/local/bin/gate-core  # sing-box 核心
/etc/systemd/system/gate@.service  # 服务模板
```

## 协议支持

| 协议 | 传输方式 | 状态 |
|------|---------|------|
| VMess | TCP / WS / gRPC / HTTP | ✅ |
| VLESS | TCP / WS / Reality / gRPC | ✅ |
| Trojan | TCP / WS | ✅ |
| Shadowsocks | 2022-blake3 | ✅ |
| Hysteria2 | UDP | ✅ |
| TUIC | UDP | ✅ |

## 许可证

Apache 2.0

## 鸣谢

- [sing-box](https://github.com/SagerNet/sing-box) — 核心引擎
