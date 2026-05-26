# 命令速查表

输入 `gate` 即可进入交互菜单，或者直接使用以下子命令：

| 命令 | 功能 | 说明 |
| :--- | :--- | :--- |
| `gate` | 交互面板 | 启动文本菜单 |
| `gate info` | 节点信息 | 显示当前端口、协议、用户数 |
| `gate -v` | 版本信息 | 显示脚本和核心版本 |
| `gate start` | 启动服务 | **自动拉取最新配置** |
| `gate restart` | 重启服务 | **自动拉取最新配置** |
| `gate stop` | 停止服务 | |
| `gate status` | 状态检查 | 检查 systemd 状态 |
| `gate log` | 实时日志 | 滚动显示日志 |
| `gate error` | 错误日志 | 仅显示 ERROR 级别 |
| `gate fetch` | 手动拉取 | 仅更新配置文件，不重启 |
| `gate test` | 连通性测试 | 测试面板 API 是否通畅 |
| `gate update` | 更新脚本 | 从 GitHub 更新自身 |
| `gate clear` | 清理日志 | 释放磁盘空间 |
| `gate uninstall`| 卸载 | 清理所有文件 |
