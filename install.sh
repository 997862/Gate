#!/bin/bash
# Gate 代理网关一键安装脚本
# 核心: sing-box (开源 Apache 2.0)

export LANG=zh_CN.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 版本信息
GATE_VERSION="1.0.0"
SINGBOX_VERSION="1.13.12"
GITHUB_REPO="https://raw.githubusercontent.com/997862/Gate/main"

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}[错误] 请使用 root 用户运行安装脚本！${PLAIN}" && exit 1
}

check_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)  SINGBOX_ARCH="amd64" ;;
        aarch64) SINGBOX_ARCH="arm64" ;;
        armv7l)  SINGBOX_ARCH="armv7" ;;
        *)       echo -e "${RED}[错误] 不支持的架构: $arch${PLAIN}" && exit 1 ;;
    esac
}

install_deps() {
    echo -e "${BLUE}[1/5]${PLAIN} 正在安装系统依赖..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y && apt-get install -y curl socat cron openssl jq 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y curl socat crond openssl jq 2>/dev/null
    fi
    echo -e "${GREEN}[完成]${PLAIN} 依赖安装完成"
}

install_singbox() {
    echo -e "${BLUE}[2/5]${PLAIN} 正在下载 sing-box 核心..."
    local url="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}.tar.gz"
    
    curl -L -o /tmp/sing-box.tar.gz "$url"
    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    cp /tmp/sing-box-${SINGBOX_VERSION}-linux-${SINGBOX_ARCH}/sing-box /usr/local/bin/gate-core
    chmod +x /usr/local/bin/gate-core
    rm -rf /tmp/sing-box*
    
    echo -e "${GREEN}[完成]${PLAIN} sing-box ${SINGBOX_VERSION} 已安装"
}

install_manager() {
    echo -e "${BLUE}[3/5]${PLAIN} 正在安装 Gate 管理脚本..."
    curl -L -o /usr/bin/gate "${GITHUB_REPO}/gate-manager.sh"
    chmod +x /usr/bin/gate
    echo -e "${GREEN}[完成]${PLAIN} 管理脚本已安装"
}

install_systemd() {
    echo -e "${BLUE}[4/5]${PLAIN} 正在配置 systemd 服务..."
    mkdir -p /etc/gate
    
    cat > /etc/systemd/system/gate@.service << 'SERVICE'
[Unit]
Description=Gate 代理服务节点 (%i)
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gate-core run -c /etc/gate/%i.json
Restart=on-failure
RestartSec=5
LimitNOFILE=51200
LimitNPROC=51200

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    echo -e "${GREEN}[完成]${PLAIN} systemd 服务已配置"
}

generate_conf() {
    echo -e "${BLUE}[5/5]${PLAIN} 正在生成配置文件..."
    if [[ ! -f /etc/gate/gate.conf ]]; then
        curl -L -o /etc/gate/gate.conf "${GITHUB_REPO}/gate.conf.example"
        echo -e "${GREEN}[完成]${PLAIN} 配置文件已生成: /etc/gate/gate.conf"
    else
        echo -e "${YELLOW}[跳过]${PLAIN} 配置文件已存在"
    fi
}

finish() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${GREEN}   Gate 安装完成！${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo ""
    echo -e "版本: ${BOLD}Gate v${GATE_VERSION}${PLAIN}"
    echo -e "核心: ${BOLD}sing-box v${SINGBOX_VERSION}${PLAIN}"
    echo ""
    echo -e "${BOLD}快速开始:${PLAIN}"
    echo "  1. 编辑配置: gate config"
    echo "  2. 测试对接: gate test"
    echo "  3. 启动服务: gate start"
    echo "  4. 查看状态: gate status"
    echo ""
    echo -e "${BOLD}常用命令:${PLAIN}"
    echo "  gate            - 交互式管理面板"
    echo "  gate restart    - 重启节点"
    echo "  gate update     - 更新 Gate"
    echo "  gate log        - 查看实时日志"
    echo "  gate uninstall  - 完全卸载"
    echo ""
    echo -e "文档: ${BLUE}https://github.com/997862/Gate${PLAIN}"
    echo ""
    
    # 自动启动管理面板
    read -p "是否立即启动管理面板？[Y/n] " answer
    if [[ "$answer" != "n" && "$answer" != "N" ]]; then
        gate
    fi
}

# 主流程
check_root
check_arch
install_deps
install_singbox
install_manager
install_systemd
generate_conf
finish
