#!/bin/bash
# Gate 代理网关一键安装脚本
# 核心: sing-box (开源 Apache 2.0)
# 源码完全公开，支持二开

export LANG=zh_CN.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'
BOLD='\033[1m'

# 版本信息
GATE_VERSION="1.2.0"
GITHUB_REPO="https://raw.githubusercontent.com/997862/Gate/main"

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}[错误] 请使用 root 用户运行安装脚本！${PLAIN}" && exit 1
}

install_deps() {
    echo -e "${BLUE}[1/4]${PLAIN} 正在安装系统依赖..."
    if command -v apt-get &>/dev/null; then
        apt-get update -y && apt-get install -y curl socat cron openssl jq python3 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y curl socat crond openssl jq python3 2>/dev/null
    fi
    echo -e "${GREEN}[完成]${PLAIN} 依赖安装完成"
}

install_core() {
    echo -e "${BLUE}[2/4]${PLAIN} 正在下载 Gate 核心 (来自 GitHub 源码)..."
    
    # 从项目仓库直接下载核心二进制文件，不再依赖外部源
    local arch=$(uname -m)
    local core_file="gate-core"
    if [[ "$arch" == "x86_64" ]]; then
        core_file="gate-core-amd64"
    elif [[ "$arch" == "aarch64" ]]; then
        core_file="gate-core-arm64"
    fi

    local url="${GITHUB_REPO}/bin/${core_file}"
    
    if curl -L -o /usr/local/bin/gate-core "$url"; then
        chmod +x /usr/local/bin/gate-core
        echo -e "${GREEN}[完成]${PLAIN} Gate 核心已安装"
    else
        echo -e "${RED}[错误] 核心下载失败！${PLAIN}"
        exit 1
    fi
}

install_manager() {
    echo -e "${BLUE}[3/4]${PLAIN} 正在安装 Gate 管理脚本..."
    curl -L -o /usr/bin/gate "${GITHUB_REPO}/gate-manager.sh"
    chmod +x /usr/bin/gate
    echo -e "${GREEN}[完成]${PLAIN} 管理脚本已安装"
}

install_systemd() {
    echo -e "${BLUE}[4/4]${PLAIN} 正在配置 systemd 服务..."
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
    if [[ ! -f /etc/gate/gate.conf ]]; then
        echo -e "${BLUE}[初始化]${PLAIN} 生成默认配置文件..."
        curl -L -o /etc/gate/gate.conf "${GITHUB_REPO}/gate.conf.example"
    else
        echo -e "${YELLOW}[跳过]${PLAIN} 配置文件已存在"
    fi
}

finish() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${GREEN}   Gate 安装完成！v${GATE_VERSION}${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo ""
    echo -e "项目地址: ${BLUE}https://github.com/997862/Gate${PLAIN}"
    echo -e "文档地址: ${BLUE}https://github.com/997862/Gate/blob/main/docs/${PLAIN}"
    echo ""
    echo -e "${BOLD}快速开始:${PLAIN}"
    echo "  1. 编辑配置: gate config"
    echo "  2. 启动服务: gate start (自动拉取面板配置并设为开机自启)"
    echo "  3. 开启监控: gate monitor start (自动维护内存/日志/更新)"
    echo ""
    echo -e "${BOLD}常用命令:${PLAIN}"
    echo "  gate            - 交互式管理面板"
    echo "  gate restart    - 重启节点"
    echo "  gate update     - 更新 Gate"
    echo "  gate log        - 查看实时日志"
    echo ""
    
    read -p "是否立即启动管理面板？[Y/n] " answer
    if [[ "$answer" != "n" && "$answer" != "N" ]]; then
        gate
    fi
}

# 主流程
check_root
install_deps
install_core
install_manager
install_systemd
generate_conf
finish
