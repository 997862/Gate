#!/bin/bash
# Gate 代理网关管理脚本 v1.3.3
# 新增 Shadowsocks 支持 (免证书/免对时) (自动根据面板地址生成证书)

export LANG=zh_CN.UTF-8
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'
BOLD='\033[1m'

CONF_DIR="/etc/gate"
CONF_FILE="$CONF_DIR/gate.conf"
CORE_BIN="/usr/local/bin/gate-core"
SCRIPT_URL="https://raw.githubusercontent.com/997862/Gate/main/gate-manager.sh"

mkdir -p "$CONF_DIR"

info() { echo -e "${BLUE}[Gate]${PLAIN} $1"; }
success() { echo -e "${GREEN}[Gate]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[Gate]${PLAIN} $1"; }
error() { echo -e "${RED}[Gate]${PLAIN} $1"; }

check_root() { [[ $EUID -ne 0 ]] && error "请使用 root 用户运行！" && exit 1; }

check_core() {
    if [[ ! -f "$CORE_BIN" ]]; then
        error "未检测到 Gate 核心，请先运行安装脚本！"
        exit 1
    fi
}

get_conf_val() { grep "^${1}=" "$CONF_FILE" 2>/dev/null | cut -d= -f2-; }
get_node_id() { get_conf_val "node_id"; }
check_config() {
    local url=$(get_conf_val "webapi_url")
    local key=$(get_conf_val "webapi_key")
    local nid=$(get_node_id)
    [[ -z "$url" || -z "$key" || -z "$nid" ]] && return 1
    return 0
}

# ============================================================
# 初始配置向导
# ============================================================
setup_wizard() {
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate 初始配置向导 (v1.3.3)${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo ""
    echo "欢迎使用 Gate！只需几步即可连接您的面板。"
    echo ""
    
    # 1. API 地址
    read -p "1. 请输入面板 API 地址 (例如 https://panel.example.com): " webapi_url
    while [[ -z "$webapi_url" ]]; do
        echo -e "${RED}   地址不能为空！${PLAIN}"
        read -p "   请重新输入: " webapi_url
    done
    # 去除末尾斜杠
    webapi_url=${webapi_url%/}

    # 2. 密钥
    read -p "2. 请输入 WebAPI 密钥 (在面板节点设置中获取): " webapi_key
    while [[ -z "$webapi_key" ]]; do
        echo -e "${RED}   密钥不能为空！${PLAIN}"
        read -p "   请重新输入: " webapi_key
    done

    # 3. 节点 ID
    read -p "3. 请输入节点 ID (对应面板后台的节点编号): " node_id
    while [[ -z "$node_id" ]]; do
        echo -e "${RED}   ID 不能为空！${PLAIN}"
        read -p "   请重新输入: " node_id
    done

    # 4. 面板类型
    echo ""
    echo "请选择面板类型："
    echo "  1. Xboard (推荐)"
    echo "  2. V2board"
    read -p "请输入选项 [1-2] (默认 1): " panel_type
    case $panel_type in
        2) type_str="v2board" ;;
        *) type_str="xboard" ;;
    esac

    echo ""
    info "正在保存配置到 $CONF_FILE ..."
    
    cat > "$CONF_FILE" << EOF
# Gate 配置文件
type=$type_str
server_type=vmess
node_id=$node_id
api=webapi
webapi_url=$webapi_url
webapi_key=$webapi_key
mem_threshold=80
EOF

    success "配置已保存！"
    echo ""
    cmd_start
}

# ============================================================
# 核心功能：从面板拉取配置 (适配 UniProxy API)
# ============================================================
cmd_fetch() {
    check_core
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    local node_id=$(get_node_id)
    
    [[ -z "$node_id" ]] && error "未配置 node_id！请运行 'gate setup' 进行配置" && exit 1
    [[ -z "$webapi_url" || -z "$webapi_key" ]] && error "未配置 webapi_url 或 webapi_key！" && exit 1
    
    info "正在从面板拉取节点 ${node_id} 配置..."
    
    # 1. 获取节点基础配置
    local node_config
    node_config=$(curl -s --connect-timeout 10 "${webapi_url}/api/v1/server/UniProxy/config?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    
    if ! echo "$node_config" | grep -q '"server_port"'; then
        error "无法获取节点配置！请检查 API 地址、密钥、节点 ID 是否正确"
        echo "API 返回: $node_config"
        return 1
    fi
    
    # 2. 获取用户列表
    local user_list
    user_list=$(curl -s --connect-timeout 10 "${webapi_url}/api/v1/server/UniProxy/user?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    if ! echo "$user_list" | grep -q '"users"'; then
        warn "无法获取用户列表"
        user_list='{"users":[]}'
    fi
    
    # 3. 生成 JSON
    python3 << PYTHON_SCRIPT
import json

node_conf = json.loads('${node_config}')
user_conf = json.loads('${user_list}')
port = node_conf.get('server_port', 443)
proto = node_conf.get('protocol', 'vmess').lower()
net = node_conf.get('network', 'tcp').lower()

# Trojan 协议需要 password 字段，其他协议使用 uuid
if proto == 'trojan':
    users = [{'password': u['uuid']} for u in user_conf.get('users', [])]
else:
    users = [{'uuid': u['uuid']} for u in user_conf.get('users', [])]

# 证书路径
cert_dir = '${CONF_DIR}/certs'
crt_path = f'{cert_dir}/trojan.crt'
key_path = f'{cert_dir}/trojan.key'
node_host = node_conf.get('host', 'trojan')

import subprocess as sb
import os as os_mod
if not os_mod.path.exists(crt_path):
    os_mod.makedirs(cert_dir, exist_ok=True)
    sb.run(f"openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -keyout {key_path} -out {crt_path} -subj '/CN={node_host}'", shell=True)

inbound_config = {
    'type': proto,
    'listen': '::',
    'listen_port': port,
    'users': users if users else [{'uuid': '00000000-0000-0000-0000-000000000000'}]
}

# Shadowsocks requires method
if proto == 'shadowsocks':
    inbound_config['method'] = node_conf.get('cipher', 'aes-256-gcm')
    inbound_config['network'] = node_conf.get('network', 'tcp')

# TLS handling (Skip for Shadowsocks)
if node_conf.get('tls') == 1 and proto != 'shadowsocks':
    inbound_config['tls'] = {
        'enabled': True,
        'certificate_path': crt_path,
        'key_path': key_path,
        'server_name': node_host
    }

cfg = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [inbound_config],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}]
}

if net == 'ws':
    cfg['inbounds'][0]['transport'] = {'type': 'ws', 'path': node_conf.get('networkSettings', {}).get('path', '/')}
elif net == 'grpc':
    cfg['inbounds'][0]['transport'] = {'type': 'grpc', 'service_name': node_conf.get('networkSettings', {}).get('serviceName', 'GunService')}

with open('${CONF_DIR}/${node_id}.json', 'w') as f:
    json.dump(cfg, f, indent=2)

print(f"SUCCESS: Port {port}, Proto {proto}, Users {len(users)}")
PYTHON_SCRIPT

    success "配置已生成！"
}

cmd_fetch_silent() { cmd_fetch >/dev/null 2>&1; }

# ============================================================
# 常用命令
# ============================================================
cmd_start() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    
    if ! check_config; then
        warn "配置不完整，启动配置向导..."
        setup_wizard
        return
    fi
    
    info "拉取最新面板配置..."
    cmd_fetch_silent
    
    info "启动节点 ${nid} 并设置开机自启..."
    systemctl enable "gate@${nid}" >/dev/null 2>&1
    systemctl start "gate@${nid}"
    sleep 1
    systemctl is-active --quiet "gate@${nid}" && success "节点已启动" || error "启动失败"
}

cmd_restart() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    
    info "拉取最新面板配置..."
    cmd_fetch_silent
    
    info "重启节点 ${nid}..."
    systemctl restart "gate@${nid}"
    sleep 2
    systemctl is-active --quiet "gate@${nid}" && success "节点已重启" || error "重启失败"
}

cmd_stop() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    info "正在停止节点..."
    systemctl stop "gate@${nid}"
    success "节点已停止"
}

cmd_status() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && { systemctl list-units "gate@*.service" --no-legend; return; }
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate 节点状态 - 节点 ${nid}${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    
    local status=$(systemctl is-active "gate@${nid}" 2>/dev/null)
    [[ "$status" == "active" ]] && echo -e "状态: ${GREEN}● 运行中${PLAIN}" || echo -e "状态: ${RED}● 已停止${PLAIN}"
    
    echo ""
    systemctl status "gate@${nid}" --no-pager -l 2>/dev/null | head -15
}

cmd_info() {
    check_core
    local nid=$(get_node_id)
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate 节点信息${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    
    if [[ -f "$CONF_DIR/${nid}.json" ]]; then
        python3 -c "
import json
with open('${CONF_DIR}/${nid}.json') as f:
    d = json.load(f)
    print(f\"协议: {d['inbounds'][0]['type']}\")
    print(f\"端口: {d['inbounds'][0]['listen_port']}\")
    print(f\"用户数: {len(d['inbounds'][0]['users'])}\")
"
    fi
    echo ""
    echo "监控状态: $(crontab -l 2>/dev/null | grep -q 'gate-monitor' && echo '已开启' || echo '未开启')"
}

cmd_log() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    journalctl -u "gate@${nid}" -f --no-pager
}

cmd_error() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    journalctl -u "gate@${nid}" -p err --no-pager
}

cmd_clear() {
    info "正在清理日志..."
    journalctl --rotate
    journalctl --vacuum-time=30d
n# 心跳上报：向面板报告节点在线
NODE_ID=$(grep "^node_id=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
TOKEN=$(grep "^webapi_key=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
API_URL=$(grep "^webapi_url=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
if [ -n "$NODE_ID" ] && [ -n "$TOKEN" ] && [ -n "$API_URL" ]; then
    curl -s -X POST "${API_URL}/api/v1/server/UniProxy/push?node_id=${NODE_ID}&token=${TOKEN}" \
         -H "Content-Type: application/json" \
         -d '{"data":[]}' >/dev/null 2>&1
fi
    success "已清理 30 天前的日志"
}

cmd_version() {
    echo -e "${BOLD}Gate Version:${PLAIN} v1.3.3"
    echo -e "${BOLD}Core Version:${PLAIN} $($CORE_BIN version | head -1)"
}

cmd_update() {
    info "正在检查更新..."
    if curl -Ls -o /usr/bin/gate "$SCRIPT_URL"; then
        chmod +x /usr/bin/gate
        success "Gate 脚本已更新！正在重启以应用新版本..."
        sleep 1
        exec /usr/bin/gate "$@"
    else
        error "更新失败"
    fi
}

cmd_uninstall() {
    warn "确定要卸载 Gate 吗？"
    read -p "输入 yes 确认: " confirm
    [[ "$confirm" != "yes" ]] && return
    
    info "正在卸载..."
    crontab -l 2>/dev/null | grep -v 'gate-monitor' | crontab -
    for nid in $(systemctl list-units "gate@*.service" --no-legend | grep -oP 'gate@\K[0-9]+'); do
        systemctl stop "gate@${nid}" 2>/dev/null; systemctl disable "gate@${nid}" 2>/dev/null
    done
    rm -f /usr/bin/gate /usr/local/bin/gate-core /etc/systemd/system/gate@.service
    rm -rf "$CONF_DIR"
    systemctl daemon-reload && systemctl reset-failed
    success "Gate 已完全卸载"
}

# ============================================================
# 内存监控 & 自动维护
# ============================================================
cmd_monitor_setup() {
    local action=$1
    local threshold=$(get_conf_val "mem_threshold")
    threshold=${threshold:-80}
    
    local monitor_script="/etc/gate/gate-monitor.sh"
    mkdir -p /etc/gate
    
    cat > "$monitor_script" << 'MEOF'
#!/bin/bash
CONF_FILE="/etc/gate/gate.conf"
NODE_ID=$(grep "^node_id=" $CONF_FILE 2>/dev/null | cut -d= -f2)
THRESHOLD=$(grep "^mem_threshold=" $CONF_FILE 2>/dev/null | cut -d= -f2)
THRESHOLD=${THRESHOLD:-80}

usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
if [ "$usage" -gt "$THRESHOLD" ]; then
    sync; echo 3 > /proc/sys/vm/drop_caches
    systemctl restart gate@$NODE_ID
    echo "$(date) - Mem usage ${usage}% > ${THRESHOLD}%, restarted" >> /var/log/gate-monitor.log
fi
journalctl --vacuum-time=30d
n# 心跳上报：向面板报告节点在线
NODE_ID=$(grep "^node_id=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
TOKEN=$(grep "^webapi_key=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
API_URL=$(grep "^webapi_url=" /etc/gate/gate.conf 2>/dev/null | cut -d= -f2)
if [ -n "$NODE_ID" ] && [ -n "$TOKEN" ] && [ -n "$API_URL" ]; then
    curl -s -X POST "${API_URL}/api/v1/server/UniProxy/push?node_id=${NODE_ID}&token=${TOKEN}" \
         -H "Content-Type: application/json" \
         -d '{"data":[]}' >/dev/null 2>&1
fi
MEOF
    chmod +x "$monitor_script"
    
    if [[ "$action" == "start" ]]; then
        (crontab -l 2>/dev/null; echo "*/5 * * * * $monitor_script") | crontab -
        success "内存监控已开启 (阈值: ${threshold}%)"
    elif [[ "$action" == "stop" ]]; then
        crontab -l 2>/dev/null | grep -v 'gate-monitor' | crontab -
        success "内存监控已关闭"
    fi
}

cmd_test() {
    check_core
    local nid=$(get_node_id)
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate API 对接测试${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    
    if curl -s "${webapi_url}/api/v1/server/UniProxy/config?node_id=${nid}&token=${webapi_key}" | grep -q '"server_port"'; then
        success "面板通信正常！正在拉取配置..."
        cmd_fetch
    else
        error "面板通信失败！"
    fi
}

cmd_help() {
    echo -e "${BOLD}Gate 代理网关管理工具 v1.3.3${PLAIN}"
    echo ""
    echo "  gate              启动交互面板"
    echo "  gate setup        启动配置向导"
    echo "  gate start        启动服务 (自动拉取)"
    echo "  gate restart      重启服务"
    echo "  gate stop         停止服务"
    echo "  gate status       查看状态"
    echo "  gate info         查看节点信息"
    echo "  gate log          实时日志"
    echo "  gate error        错误日志"
    echo "  gate monitor      内存监控管理"
    echo "  gate update       更新脚本 (自动重启)"
    echo "  gate uninstall    卸载"
}

cmd_interactive() {
    check_core
    
    # 检查是否需要配置
    if ! check_config; then
        warn "检测到未配置面板信息，即将启动配置向导..."
        sleep 1
        setup_wizard
        return
    fi

    while true; do
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo -e "${BOLD}        Gate 代理网关管理面板 v1.3.3${PLAIN}"
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo "  1. 查看节点信息 (info)"
        echo "  2. 启动服务 (start)"
        echo "  3. 重启服务 (restart)"
        echo "  4. 停止服务 (stop)"
        echo "  5. 查看实时日志 (log)"
        echo "  6. 查看错误日志 (error)"
        echo "  7. 内存监控管理 (monitor)"
        echo "  8. 重新配置 (setup)"
        echo "  9. 更新 Gate (update)"
        echo "  10. 完全卸载 (uninstall)"
        echo "  0. 退出"
        read -p "请选择 [0-10]: " choice
        case $choice in
            1) cmd_info; ;; 2) cmd_start; ;; 3) cmd_restart; ;; 4) cmd_stop; ;; 
            5) cmd_log; ;; 6) cmd_error; ;; 7) read -p "开启(y)/关闭(n)? " ans; [[ "$ans" == "y" ]] && cmd_monitor_setup start || cmd_monitor_setup stop; ;;
            8) setup_wizard; ;; 9) cmd_update; ;; 10) cmd_uninstall; exit 0; ;; 0) exit 0; ;; *) warn "无效选择"; ;;
        esac
        read -p "按回车键继续..."
        clear
    done
}

# Main Entry
case "${1:-}" in
    start) cmd_start; ;; stop) cmd_stop; ;; restart) cmd_restart; ;;
    setup) setup_wizard; ;; status) cmd_status; ;; info) cmd_info; ;;
    log) cmd_log; ;; error) cmd_error; ;; clear) cmd_clear; ;;
    test) cmd_test; ;; update) cmd_update; ;; uninstall) cmd_uninstall; ;;
    monitor) cmd_monitor_setup "${2:-status}"; ;;
    -v|--version) cmd_version; ;; help|--help|-h) cmd_help; ;;
    *) cmd_interactive; ;;
esac
