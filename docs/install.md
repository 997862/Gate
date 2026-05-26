# 快速安装与配置

## 1. 一键安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)
```

## 2. 配置向导

**Gate v1.3.0 引入了全新的配置向导！**

安装完成后，只需运行：
```bash
gate
```

如果检测到未配置，系统会自动进入向导模式，依次询问：
1. 面板 API 地址
2. WebAPI 密钥
3. 节点 ID
4. 面板类型

输入完成后，Gate 会自动保存配置并启动服务。

## 3. 手动配置 (可选)

如果你想手动编辑，配置文件位于 `/etc/gate/gate.conf`。
