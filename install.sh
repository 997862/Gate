#!/bin/bash
# Gate 一键安装脚本
# 基于 Sing-box 核心，兼容多协议代理管理

export LANG=en_US.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
BOLD='\033[1m'

os_arch=""
[[ $(uname -m) == "x86_64" || $(uname -m) == "x64" || $(uname -m) == "amd64" ]] && os_arch="amd64"
[[ $(uname -m) == "aarch64" || $(uname -m) == "arm64" ]] && os_arch="arm64"

[[ -z "$os_arch" ]] && echo -e "${RED}不支持的架构: $(uname -m)${PLAIN}" && exit 1

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}" && exit 1

echo -e ""
echo -e "${GREEN}============================================${PLAIN}"
echo -e "${BOLD}          Gate (Sing-box 版) 安装脚本         ${PLAIN}"
echo -e "${GREEN}============================================${PLAIN}"
echo -e ""

install_deps() {
    echo -e "${YELLOW}[1/4] 正在安装系统依赖...${PLAIN}"
    if [[ -f /etc/redhat-release ]]; then
        yum install -y wget curl tar jq cronie openssl
    elif [[ -f /etc/debian_version ]]; then
        apt update -y && apt install -y wget curl tar jq cron openssl
    else
        echo -e "${RED}未检测到支持的操作系统，请手动安装依赖。${PLAIN}"
    fi
    echo -e "${GREEN}依赖安装完成。${PLAIN}"
}

install_singbox() {
    echo -e "${YELLOW}[2/4] 正在下载 Gate 核心 (Sing-box)...${PLAIN}"
    local version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    version=${version#v}
    [[ -z "$version" ]] && version="1.9.6" # 兜底版本

    local url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${os_arch}.tar.gz"
    echo -e "核心版本: ${BOLD}v${version}${PLAIN}"
    
    if ! wget --no-check-certificate -qO /tmp/sing-box.tar.gz "$url"; then
        echo -e "${RED}下载核心失败，请检查网络环境是否支持访问 GitHub。${PLAIN}"
        exit 1
    fi

    tar -xzf /tmp/sing-box.tar.gz -C /tmp/
    mkdir -p /usr/local/bin/
    mv /tmp/sing-box-${version}-linux-${os_arch}/sing-box /usr/local/bin/gate-core
    chmod +x /usr/local/bin/gate-core
    rm -rf /tmp/sing-box*
    echo -e "${GREEN}核心安装成功: /usr/local/bin/gate-core${PLAIN}"
}

install_manager() {
    echo -e "${YELLOW}[3/4] 正在安装 Gate 管理脚本...${PLAIN}"
    wget --no-check-certificate -qO /usr/bin/gate https://raw.githubusercontent.com/997862/Gate/main/gate-manager.sh
    chmod +x /usr/bin/gate

    echo -e "${YELLOW}[4/4] 正在配置 Systemd 服务...${PLAIN}"
    wget --no-check-certificate -qO /etc/systemd/system/gate@.service https://raw.githubusercontent.com/997862/Gate/main/gate@.service
    systemctl daemon-reload

    mkdir -p /etc/gate
    echo -e "${GREEN}Systemd 配置完成。${PLAIN}"
}

install_deps
install_singbox
install_manager

echo -e ""
echo -e "${GREEN}============================================${PLAIN}"
echo -e "${BOLD}          安装完成！                         ${PLAIN}"
echo -e "${GREEN}============================================${PLAIN}"
echo -e ""
echo -e "输入 ${GREEN}gate${PLAIN} 启动管理面板"
echo -e ""

sleep 1
gate
