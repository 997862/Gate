#!/bin/bash
# Gate 管理面板脚本

export LANG=en_US.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
BOLD='\033[1m'

CONF_DIR="/etc/gate"
mkdir -p "$CONF_DIR"

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误：请使用 root 用户运行！${PLAIN}" && exit 1
}

check_bin() {
    command -v gate-core &>/dev/null || {
        echo -e "${RED}错误：未检测到 Gate 核心。请先运行安装脚本安装。${PLAIN}"
        exit 1
    }
}

show_menu() {
    clear
    check_root
    check_bin
    echo -e "${GREEN}============================================${PLAIN}"
    echo -e "${BOLD}        Gate 代理管理面板 (Sing-box)          ${PLAIN}"
    echo -e "${GREEN}============================================${PLAIN}"
    echo -e " 1. 新建代理节点 (支持 VMess/VLESS/Trojan/SS)"
    echo -e " 2. 查看节点列表"
    echo -e " 3. 管理节点 (启动/停止/重启)"
    echo -e " 4. 查看节点配置"
    echo -e " 5. 查看运行日志"
    echo -e " 6. 更新 Gate 到最新版"
    echo -e " 7. 卸载 Gate"
    echo -e " 0. 退出"
    echo -e "${GREEN}============================================${PLAIN}"
    read -p "请输入选项编号: " choice
    case $choice in
        1) new_instance ;;
        2) list_instances ;;
        3) manage_instance ;;
        4) view_config ;;
        5) view_log ;;
        6) update_gate ;;
        7) uninstall ;;
        0) exit ;;
        *) echo -e "${RED}无效选项，请重新输入。${PLAIN}"; sleep 1; show_menu ;;
    esac
}

new_instance() {
    echo -e ""
    read -p "请输入节点名称 (英文或数字，如 node1): " name
    [[ -z "$name" ]] && echo -e "${RED}名称不能为空！${PLAIN}" && sleep 1 && show_menu
    
    if [[ -f "$CONF_DIR/$name.json" ]]; then
        echo -e "${RED}错误：节点 $name 已存在，请勿重复创建！${PLAIN}"
        sleep 2 && show_menu
    fi

    echo -e ""
    echo -e "${BOLD}请选择协议类型:${PLAIN}"
    echo -e " 1. VMess (推荐，兼容性强)"
    echo -e " 2. VLESS (高性能，支持 Reality)"
    echo -e " 3. Trojan (隐蔽性强)"
    echo -e " 4. Shadowsocks (经典，稳定)"
    echo -e " 5. Hysteria2 (抗丢包，高性能)"
    read -p "请输入协议编号: " proto

    local port=$((10000 + RANDOM % 50000))
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local pass=$(openssl rand -hex 16)

    # 生成配置文件
    case $proto in
        1) # VMess
            cat > "$CONF_DIR/$name.json" << JSONEOF
{
  // VMess 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vmess",
      "listen": "::",
      "listen_port": ${port},
      "users": [
        {
          "uuid": "${uuid}",
          "alterId": 0,
          "security": "auto"
        }
      ],
      "transport": {
        "type": "tcp" 
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
JSONEOF
            echo -e "\n${GREEN}创建 VMess 节点成功！${PLAIN}"
            echo -e "-------------------------------"
            echo -e "节点名称: ${BOLD}${name}${PLAIN}"
            echo -e "服务端口: ${BOLD}${port}${PLAIN}"
            echo -e "安全 ID  : ${BOLD}${uuid}${PLAIN}"
            echo -e "-------------------------------"
            ;;
        2) # VLESS
            cat > "$CONF_DIR/$name.json" << JSONEOF
{
  // VLESS 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": ${port},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": ""
        }
      ],
      "transport": {
        "type": "tcp"
      }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
JSONEOF
            echo -e "\n${GREEN}创建 VLESS 节点成功！${PLAIN}"
            echo -e "-------------------------------"
            echo -e "节点名称: ${BOLD}${name}${PLAIN}"
            echo -e "服务端口: ${BOLD}${port}${PLAIN}"
            echo -e "安全 ID  : ${BOLD}${uuid}${PLAIN}"
            echo -e "-------------------------------"
            ;;
        3) # Trojan
            cat > "$CONF_DIR/$name.json" << JSONEOF
{
  // Trojan 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "trojan",
      "listen": "::",
      "listen_port": ${port},
      "users": [
        {
          "password": "${pass}"
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
JSONEOF
            echo -e "\n${GREEN}创建 Trojan 节点成功！${PLAIN}"
            echo -e "-------------------------------"
            echo -e "节点名称: ${BOLD}${name}${PLAIN}"
            echo -e "服务端口: ${BOLD}${port}${PLAIN}"
            echo -e "连接密码: ${BOLD}${pass}${PLAIN}"
            echo -e "-------------------------------"
            ;;
        4) # Shadowsocks
            cat > "$CONF_DIR/$name.json" << JSONEOF
{
  // Shadowsocks 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": ${port},
      "method": "2022-blake3-aes-256-gcm",
      "password": "${pass}"
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
JSONEOF
            echo -e "\n${GREEN}创建 Shadowsocks 节点成功！${PLAIN}"
            echo -e "-------------------------------"
            echo -e "节点名称: ${BOLD}${name}${PLAIN}"
            echo -e "服务端口: ${BOLD}${port}${PLAIN}"
            echo -e "连接密码: ${BOLD}${pass}${PLAIN}"
            echo -e "加密方式: 2022-blake3-aes-256-gcm"
            echo -e "-------------------------------"
            ;;
        5) # Hysteria2
            cat > "$CONF_DIR/$name.json" << JSONEOF
{
  // Hysteria2 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": ${port},
      "users": [
        {
          "password": "${pass}"
        }
      ],
      "masquerade": "https://www.bing.com"
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
JSONEOF
            echo -e "\n${GREEN}创建 Hysteria2 节点成功！${PLAIN}"
            echo -e "-------------------------------"
            echo -e "节点名称: ${BOLD}${name}${PLAIN}"
            echo -e "服务端口: ${BOLD}${port}${PLAIN}"
            echo -e "连接密码: ${BOLD}${pass}${PLAIN}"
            echo -e "-------------------------------"
            ;;
    esac

    echo -e "\n${YELLOW}正在启动节点服务...${PLAIN}"
    systemctl enable gate@$name
    systemctl restart gate@$name
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}节点 ${name} 已成功启动并开机自启。${PLAIN}"
    else
        echo -e "${RED}节点启动失败，请查看日志排查问题。${PLAIN}"
    fi
    
    read -p "按回车键返回主菜单..."
    show_menu
}

list_instances() {
    clear
    echo -e "${BOLD}已配置的节点列表:${PLAIN}"
    echo -e "-----------------------------------"
    if ls $CONF_DIR/*.json 1> /dev/null 2>&1; then
        for f in $CONF_DIR/*.json; do
            local n=$(basename "$f" .json)
            local status=$(systemctl is-active "gate@$n" 2>/dev/null)
            local color=$GREEN
            [[ "$status" != "active" ]] && color=$RED
            echo -e " ${BOLD}${n}${PLAIN}  状态: ${color}${status}${PLAIN}"
        done
    else
        echo -e "  暂无节点。"
    fi
    echo -e "-----------------------------------"
    read -p "按回车键返回主菜单..."
    show_menu
}

manage_instance() {
    clear
    list_instances
    echo -e ""
    read -p "请输入要管理的节点名称: " name
    
    if [[ ! -f "$CONF_DIR/$name.json" ]]; then
        echo -e "${RED}错误：节点 ${name} 不存在！${PLAIN}"
        sleep 1
        show_menu
    fi

    echo -e "\n请选择操作:"
    echo -e " 1. 启动"
    echo -e " 2. 停止"
    echo -e " 3. 重启"
    read -p "选项: " act

    case $act in
        1) systemctl start gate@$name && echo -e "${GREEN}已启动${PLAIN}" ;;
        2) systemctl stop gate@$name && echo -e "${YELLOW}已停止${PLAIN}" ;;
        3) systemctl restart gate@$name && echo -e "${GREEN}已重启${PLAIN}" ;;
    esac
    
    read -p "按回车键返回主菜单..."
    show_menu
}

view_config() {
    clear
    read -p "请输入节点名称: " name
    if [[ -f "$CONF_DIR/$name.json" ]]; then
        echo -e "${BOLD}节点配置 (${name}):${PLAIN}"
        cat "$CONF_DIR/$name.json"
    else
        echo -e "${RED}未找到该节点的配置文件。${PLAIN}"
    fi
    read -p "按回车键返回主菜单..."
    show_menu
}

view_log() {
    clear
    read -p "请输入节点名称: " name
    systemctl status "gate@$name" -n 30 --no-pager
    read -p "按回车键返回主菜单..."
    show_menu
}

update_gate() {
    echo -e "${GREEN}正在拉取最新安装脚本并更新...${PLAIN}"
    curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh | bash
}

uninstall() {
    read -p "确定要彻底卸载 Gate 吗？此操作不可逆 (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        systemctl stop "gate@*" 2>/dev/null
        systemctl disable "gate@*" 2>/dev/null
        rm -f /usr/bin/gate /usr/local/bin/gate-core
        rm -f /etc/systemd/system/gate@.service
        systemctl daemon-reload
        rm -rf /etc/gate
        echo -e "${GREEN}卸载完成。${PLAIN}"
    fi
}

show_menu
