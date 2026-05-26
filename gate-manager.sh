#!/bin/bash
# Gate 管理面板脚本
# 对标 Soga 的配置文件结构与管理体验

export LANG=en_US.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
BOLD='\033[1m'

CONF_DIR="/etc/gate"
CONF_FILE="$CONF_DIR/gate.conf"
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

init_conf() {
    if [[ ! -f "$CONF_FILE" ]]; then
        cat > "$CONF_FILE" << 'EOF'
# =========================================
# Gate 配置文件 (对标 Soga 格式)
# =========================================

# --- 基础配置 ---
# 面板类型: xboard, v2board, sspanel, newboard
type=xboard
# 节点协议类型: vmess, vless, trojan, shadowsocks, hysteria2
server_type=vmess
# 节点 ID (对应面板后台生成的编号)
node_id=
# 授权密钥 (Gate 开源免费，此项留空即可)
soga_key=

# --- 对接方式 (二选一) ---
# 可选值: webapi, db, none (单机模式)
api=webapi

# --- WebAPI 对接信息 ---
# 面板 API 地址 (如 http://cloud.example.com)
webapi_url=
# 面板通信密钥 (WebAPI Key)
webapi_key=

# --- 数据库对接信息 ---
db_host=
db_port=3306
db_name=
db_user=
db_password=

# --- 证书配置 ---
# 证书模式: manual (手动), acme (自动), none (无)
cert_mode=none
# 手动证书路径
cert_file=
key_file=
# 自动证书配置
cert_domain=
cert_key_length=ec-256

# --- Proxy Protocol 中转配置 ---
# 是否开启 Proxy Protocol (true/false)
proxy_protocol=false
udp_proxy_protocol=false

# --- Redis 配置 (全局 IP 限制) ---
redis_enable=false
redis_addr=127.0.0.1:6379
redis_password=
redis_db=0
conn_limit_expiry=60

# --- 动态限速配置 ---
dy_limit_enable=false
dy_limit_duration=
dy_limit_trigger_time=60
dy_limit_trigger_speed=100
dy_limit_speed=30
dy_limit_time=600
dy_limit_white_user_id=

# --- 限制配置 ---
# 0 表示不限制
user_conn_limit=0
user_speed_limit=0
node_speed_limit=0

# --- 其他配置 ---
# 数据检查间隔 (秒)
check_interval=60
submit_interval=60
# 是否禁止 BitTorrent
forbidden_bit_torrent=true
# 日志级别: debug, info, warn, error
log_level=info
EOF
        echo -e "${GREEN}已生成默认配置文件: ${CONF_FILE}${PLAIN}"
    fi
}

show_menu() {
    clear
    check_root
    check_bin
    init_conf
    echo -e "${GREEN}============================================${PLAIN}"
    echo -e "${BOLD}        Gate 代理管理面板 (Sing-box)          ${PLAIN}"
    echo -e "${GREEN}============================================${PLAIN}"
    echo -e " 1. 查看/编辑配置文件"
    echo -e " 2. 新建代理节点 (VMess/VLESS/Trojan/SS)"
    echo -e " 3. 查看节点列表"
    echo -e " 4. 管理节点 (启动/停止/重启)"
    echo -e " 5. 查看运行日志"
    echo -e " 6. 申请/更新 SSL 证书"
    echo -e " 7. 更新 Gate 到最新版"
    echo -e " 8. 完整卸载 (删除所有配置和数据)"
    echo -e " 0. 退出"
    echo -e "${GREEN}============================================${PLAIN}"
    read -p "请输入选项编号: " choice
    case $choice in
        1) edit_conf ;;
        2) new_instance ;;
        3) list_instances ;;
        4) manage_instance ;;
        5) view_log ;;
        6) manage_cert ;;
        7) update_gate ;;
        8) full_uninstall ;;
        0) exit ;;
        *) echo -e "${RED}无效选项，请重新输入。${PLAIN}"; sleep 1; show_menu ;;
    esac
}

edit_conf() {
    clear
    echo -e "${BOLD}当前配置文件内容:${PLAIN}"
    echo -e "${YELLOW}$(cat "$CONF_FILE")${PLAIN}"
    echo -e ""
    read -p "是否使用 nano 编辑器修改? (y/n): " yn
    if [[ "$yn" == "y" ]]; then
        if command -v nano &>/dev/null; then
            nano "$CONF_FILE"
        elif command -v vi &>/dev/null; then
            vi "$CONF_FILE"
        else
            echo -e "${RED}未检测到编辑器，请手动编辑 ${CONF_FILE}${PLAIN}"
        fi
    fi
    read -p "按回车键返回主菜单..."
    show_menu
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
    read -p "请输入协议编号: " proto

    local port=$((10000 + RANDOM % 50000))
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local pass=$(openssl rand -hex 16)

    # 生成带中文注释的 JSON 配置
    case $proto in
        1) cat > "$CONF_DIR/$name.json" << EOF
{
  // VMess 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "vmess",
    "listen": "::",
    "listen_port": ${port},
    "users": [{ "uuid": "${uuid}" }]
    
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
            echo -e "\n${GREEN}创建 VMess 节点成功！${PLAIN}"
            echo -e "端口: ${BOLD}${port}${PLAIN} | UUID: ${BOLD}${uuid}${PLAIN}"
            ;;
        2) cat > "$CONF_DIR/$name.json" << EOF
{
  // VLESS 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "listen_port": ${port},
    "users": [{ "uuid": "${uuid}", "flow": "" }]
    
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
            echo -e "\n${GREEN}创建 VLESS 节点成功！${PLAIN}"
            echo -e "端口: ${BOLD}${port}${PLAIN} | UUID: ${BOLD}${uuid}${PLAIN}"
            ;;
        3) cat > "$CONF_DIR/$name.json" << EOF
{
  // Trojan 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "trojan",
    "listen": "::",
    "listen_port": ${port},
    "users": [{ "password": "${pass}" }]
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
            echo -e "\n${GREEN}创建 Trojan 节点成功！${PLAIN}"
            echo -e "端口: ${BOLD}${port}${PLAIN} | 密码: ${BOLD}${pass}${PLAIN}"
            ;;
        4) cat > "$CONF_DIR/$name.json" << EOF
{
  // Shadowsocks 节点配置
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "shadowsocks",
    "listen": "::",
    "listen_port": ${port},
    "method": "2022-blake3-aes-256-gcm",
    "password": "${pass}"
  }],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
            echo -e "\n${GREEN}创建 Shadowsocks 节点成功！${PLAIN}"
            echo -e "端口: ${BOLD}${port}${PLAIN} | 密码: ${BOLD}${pass}${PLAIN}"
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
    [[ ! -f "$CONF_DIR/$name.json" ]] && echo -e "${RED}节点不存在！${PLAIN}" && sleep 1 && show_menu

    echo -e "\n请选择操作:"
    echo -e " 1. 启动  2. 停止  3. 重启  4. 删除节点"
    read -p "选项: " act
    case $act in
        1) systemctl start gate@$name ;;
        2) systemctl stop gate@$name ;;
        3) systemctl restart gate@$name ;;
        4) systemctl stop gate@$name; systemctl disable gate@$name; rm -f "$CONF_DIR/$name.json" ;;
    esac
    echo -e "${GREEN}操作完成${PLAIN}"
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

manage_cert() {
    clear
    echo -e "${BOLD}证书管理${PLAIN}"
    echo -e " 1. 申请 Let's Encrypt 证书 (HTTP 模式)"
    echo -e " 2. 申请 Let's Encrypt 证书 (DNS 模式)"
    echo -e " 3. 查看已申请证书"
    read -p "选择: " c
    case $c in
        1)
            read -p "请输入域名: " domain
            /root/.acme.sh/acme.sh --issue -d "$domain" --standalone
            echo -e "${GREEN}证书已申请，请手动填入配置文件 cert_file 和 key_file 路径${PLAIN}"
            ;;
        2)
            read -p "请输入域名: " domain
            read -p "请输入 DNS API (如 cf_api_key): " api
            /root/.acme.sh/acme.sh --issue -d "$domain" --dns "$api"
            ;;
        3)
            /root/.acme.sh/acme.sh --list
            ;;
    esac
    read -p "按回车键返回主菜单..."
    show_menu
}

update_gate() {
    echo -e "${GREEN}正在拉取最新安装脚本并更新...${PLAIN}"
    curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh | bash
}

full_uninstall() {
    clear
    echo -e "${RED}============================================${PLAIN}"
    echo -e "${RED}${BOLD}          ⚠️ 完整卸载警告 ⚠️              ${PLAIN}"
    echo -e "${RED}============================================${PLAIN}"
    echo -e "此操作将彻底删除 Gate 的所有配置、数据和服务文件！"
    echo -e "包括:"
    echo -e " - 所有节点配置文件 (/etc/gate/)"
    echo -e " - Gate 核心程序 (/usr/local/bin/gate-core)"
    echo -e " - 管理脚本 (/usr/bin/gate)"
    echo -e " - Systemd 服务模板"
    echo -e ""
    read -p "确认要执行完整卸载吗？(输入 yes 确认): " confirm
    if [[ "$confirm" == "yes" ]]; then
        echo -e "${YELLOW}正在停止所有节点服务...${PLAIN}"
        systemctl stop "gate@*" 2>/dev/null
        systemctl disable "gate@*" 2>/dev/null
        
        echo -e "${YELLOW}正在删除系统文件...${PLAIN}"
        rm -f /usr/bin/gate
        rm -f /usr/local/bin/gate-core
        rm -f /etc/systemd/system/gate@.service
        systemctl daemon-reload
        
        echo -e "${YELLOW}正在删除配置目录...${PLAIN}"
        rm -rf /etc/gate/
        
        echo -e "${GREEN}============================================${PLAIN}"
        echo -e "${GREEN}  完整卸载完成！                                ${PLAIN}"
        echo -e "${GREEN}============================================${PLAIN}"
        echo -e ""
        exit 0
    else
        echo -e "${YELLOW}已取消卸载操作。${PLAIN}"
        sleep 1
        show_menu
    fi
}

show_menu
