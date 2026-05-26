#!/bin/bash
# Gate 代理网关管理脚本
# 命令: gate [restart|update|log|status|clear|uninstall|start|stop|config|test|fetch]

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

check_root() {
    [[ $EUID -ne 0 ]] && error "请使用 root 用户运行！" && exit 1
}

check_core() {
    if [[ ! -f "$CORE_BIN" ]]; then
        error "未检测到 Gate 核心，请先运行安装脚本！"
        exit 1
    fi
}

get_conf_val() { grep "^${1}=" "$CONF_FILE" 2>/dev/null | cut -d= -f2-; }
get_node_id() { get_conf_val "node_id"; }

# ============================================================
# 核心功能：从面板拉取配置 (对齐 Xboard UniProxy API)
# ============================================================
cmd_fetch() {
    check_core
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    local node_id=$(get_node_id)
    
    [[ -z "$node_id" ]] && error "未配置 node_id！" && exit 1
    [[ -z "$webapi_url" || -z "$webapi_key" ]] && error "未配置 webapi_url 或 webapi_key！" && exit 1
    
    info "正在从面板拉取节点 ${node_id} 配置..."
    
    # 1. 获取节点基础配置 (端口、协议、网络)
    # Xboard 标准 UniProxy 接口
    local node_config
    node_config=$(curl -s --connect-timeout 10 "${webapi_url}/api/v1/server/UniProxy/config?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    
    if ! echo "$node_config" | grep -q '"server_port"'; then
        error "无法获取节点配置！请检查 API 地址、密钥、节点 ID 是否正确"
        echo "API 返回: $node_config"
        return 1
    fi
    
    # 解析面板返回的配置
    local server_port=$(echo "$node_config" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('server_port', 0))")
    local protocol=$(echo "$node_config" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('protocol', 'vmess'))")
    local network=$(echo "$node_config" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('network', 'tcp'))")
    
    success "获取到节点配置: 端口=${server_port}, 协议=${protocol}, 网络=${network}"
    
    # 2. 获取用户列表
    local user_list
    user_list=$(curl -s --connect-timeout 10 "${webapi_url}/api/v1/server/UniProxy/user?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    
    if ! echo "$user_list" | grep -q '"users"'; then
        warn "无法获取用户列表，将使用空配置"
        user_list='{"users":[]}'
    fi
    
    # 3. 生成 sing-box JSON 配置
    python3 << PYTHON_SCRIPT
import json, sys

node_conf = json.loads('''$node_config''')
user_conf = json.loads('''$user_list''')

server_port = node_conf.get('server_port', 443)
protocol = node_conf.get('protocol', 'vmess').lower()
network = node_conf.get('network', 'tcp').lower()

users = []
for u in user_conf.get('users', []):
    if protocol in ['vmess', 'vless']:
        users.append({
            'uuid': u['uuid'],
            'alter_id': 0, # sing-box 1.9+ ignores this but for compat
            'flow': u.get('flow', '') if protocol == 'vless' else ''
        })
    elif protocol == 'trojan':
        users.append({'password': u.get('password', u.get('uuid', ''))})
    elif protocol in ['shadowsocks', 'ss']:
        # Note: Xboard might return passwords differently for SS
        users.append({'password': u.get('password', ''), 'method': '2022-blake3-aes-128-gcm'})

# 构建 sing-box inbound
inbound = {
    'type': protocol,
    'listen': '::',
    'listen_port': server_port,
    'users': users
}

# 网络配置
if network == 'ws':
    ws_path = node_conf.get('networkSettings', {}).get('path', '/')
    ws_host = node_conf.get('networkSettings', {}).get('headers', {}).get('Host', '')
    inbound['transport'] = {
        'type': 'ws',
        'path': ws_path,
        'headers': {'Host': ws_host} if ws_host else {}
    }
elif network == 'grpc':
    inbound['transport'] = {
        'type': 'grpc',
        'service_name': node_conf.get('networkSettings', {}).get('serviceName', 'GunService')
    }
elif network == 'h2':
    inbound['transport'] = {
        'type': 'http',
        'path': node_conf.get('networkSettings', {}).get('path', '/'),
        'host': node_conf.get('networkSettings', {}).get('host', [])
    }
elif network == 'http':
    inbound['transport'] = {
        'type': 'http',
        'host': node_conf.get('networkSettings', {}).get('host', []),
        'path': node_conf.get('networkSettings', {}).get('path', '/')
    }

# TLS 配置
tls_setting = node_conf.get('tls', 0)
if tls_setting == 1 or tls_setting == True:
    inbound['tls'] = {
        'enabled': True,
        'server_name': node_conf.get('server_name', ''),
        'certificate_path': '/etc/gate/cert.pem',
        'key_path': '/etc/gate/key.pem'
    }

config = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [inbound],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}]
}

with open('${CONF_DIR}/${node_id}.json', 'w') as f:
    # 添加注释风格的 JSON
    json_str = json.dumps(config, indent=2)
    f.write(f'{{\n  // Gate 自动生成的节点配置 (来自面板)\n  "log": {json_str.split("log")[1].split("outbounds")[0]} \n  "outbounds": [{{ "type": "direct", "tag": "direct" }}]\n}}')

print(f"Generated config for port {server_port} with {len(users)} users")
PYTHON_SCRIPT

    if [[ $? -eq 0 ]]; then
        success "节点 ${node_id} 配置已生成！"
        echo -e "配置文件: ${CONF_DIR}/${node_id}.json"
        info "运行 'gate restart' 使配置生效"
    else
        error "配置生成失败！"
        return 1
    fi
}

# ============================================================
# 静默拉取 (用于 start/restart)
# ============================================================
cmd_fetch_silent() {
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    local node_id=$(get_node_id)
    
    [[ -z "$node_id" || -z "$webapi_url" ]] && return 1
    
    local node_config
    node_config=$(curl -s --connect-timeout 5 "${webapi_url}/api/v1/server/UniProxy/config?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    
    if echo "$node_config" | grep -q '"server_port"'; then
        local user_list
        user_list=$(curl -s --connect-timeout 5 "${webapi_url}/api/v1/server/UniProxy/user?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
        
        # Generate JSON silently
        python3 -c "
import json
node = json.loads('$node_config')
users_json = json.loads('$user_list')
port = node.get('server_port', 443)
proto = node.get('protocol', 'vmess')
net = node.get('network', 'tcp')
users = [{'uuid': u['uuid']} for u in users_json.get('users', [])]
cfg = {'log': {'level': 'info', 'timestamp': True}, 'inbounds': [{'type': proto, 'listen': '::', 'listen_port': port, 'users': users}], 'outbounds': [{'type': 'direct', 'tag': 'direct'}]}
if net == 'ws':
    cfg['inbounds'][0]['transport'] = {'type': 'ws', 'path': node.get('networkSettings', {}).get('path', '/')}
import os
os.makedirs('${CONF_DIR}', exist_ok=True)
with open('${CONF_DIR}/${node_id}.json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null
    fi
}

# ============================================================
# 常用命令
# ============================================================
cmd_start() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    
    info "正在拉取最新面板配置..."
    cmd_fetch_silent
    
    info "正在启动节点 ${nid}..."
    systemctl start "gate@${nid}"
    sleep 1
    systemctl is-active --quiet "gate@${nid}" && success "节点 ${nid} 启动成功！" || error "启动失败"
}

cmd_stop() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    info "正在停止节点 ${nid}..."
    systemctl stop "gate@${nid}"
    success "节点 ${nid} 已停止！"
}

cmd_restart() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    
    info "正在拉取最新面板配置..."
    cmd_fetch_silent
    
    info "正在重启节点 ${nid}..."
    systemctl restart "gate@${nid}"
    sleep 2
    systemctl is-active --quiet "gate@${nid}" && success "节点 ${nid} 重启成功！" || error "重启失败"
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

cmd_log() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    journalctl -u "gate@${nid}" -f --no-pager
}

cmd_clear() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    journalctl --rotate && journalctl --vacuum-time=1s
    success "日志已清除！"
}

cmd_test() {
    check_core
    local nid=$(get_node_id)
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate API 对接测试${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "节点 ID: ${BOLD}${nid}${PLAIN}"
    
    if curl -s "${webapi_url}/api/v1/server/UniProxy/config?node_id=${nid}&token=${webapi_key}" | grep -q '"server_port"'; then
        success "面板通信正常！正在拉取配置..."
        cmd_fetch
    else
        error "面板通信失败！请检查 API 地址、密钥、节点 ID。"
    fi
}

cmd_config() {
    [[ ! -f "$CONF_FILE" ]] && error "配置文件不存在！" && exit 1
    ${EDITOR:-nano} "$CONF_FILE"
    success "配置已保存！"
}

cmd_update() {
    info "正在检查更新..."
    cp /usr/bin/gate /usr/bin/gate.bak.$(date +%Y%m%d)
    if curl -Ls -o /usr/bin/gate "$SCRIPT_URL"; then
        chmod +x /usr/bin/gate
        success "Gate 已更新！"
        cmd_restart
    else
        error "更新失败！"
    fi
}

cmd_uninstall() {
    warn "确定要卸载 Gate 吗？此操作将删除所有配置！"
    read -p "输入 yes 确认卸载: " confirm
    [[ "$confirm" != "yes" ]] && return
    
    info "正在卸载 Gate..."
    for nid in $(systemctl list-units "gate@*.service" --no-legend | grep -oP 'gate@\K[0-9]+'); do
        systemctl stop "gate@${nid}" 2>/dev/null; systemctl disable "gate@${nid}" 2>/dev/null
    done
    rm -f /usr/bin/gate /usr/local/bin/gate-core /etc/systemd/system/gate@.service
    rm -rf "$CONF_DIR"
    systemctl daemon-reload && systemctl reset-failed
    success "Gate 已完全卸载！"
}

cmd_help() {
    echo -e "${BOLD}Gate 代理网关管理工具${PLAIN}"
    echo ""
    echo "  gate fetch        从面板拉取节点配置"
    echo "  gate start        启动节点"
    echo "  gate restart      重启节点"
    echo "  gate stop         停止节点"
    echo "  gate status       查看状态"
    echo "  gate log          实时日志"
    echo "  gate clear        清除日志"
    echo "  gate test         测试 API"
    echo "  gate config       编辑配置"
    echo "  gate update       更新 Gate"
    echo "  gate uninstall    完全卸载"
}

cmd_interactive() {
    check_core
    while true; do
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo -e "${BOLD}        Gate 代理网关管理面板${PLAIN}"
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo "  1. 拉取面板配置 (fetch)"
        echo "  2. 查看节点状态"
        echo "  3. 重启节点服务"
        echo "  4. 查看实时日志"
        echo "  5. 编辑配置文件"
        echo "  6. 测试 API 对接"
        echo "  7. 更新 Gate"
        echo "  8. 清除日志"
        echo "  9. 完全卸载"
        echo "  0. 退出"
        read -p "请选择 [0-9]: " choice
        case $choice in
            1) cmd_fetch; ;; 2) cmd_status; ;; 3) cmd_restart; ;; 4) cmd_log; ;;
            5) cmd_config; ;; 6) cmd_test; ;; 7) cmd_update; ;; 8) cmd_clear; ;;
            9) cmd_uninstall; exit 0; ;; 0) exit 0; ;; *) warn "无效选择！"; ;;
        esac
        read -p "按回车键继续..."
        clear
    done
}

case "${1:-}" in
    start) cmd_start; ;; stop) cmd_stop; ;; restart) cmd_restart; ;;
    fetch) cmd_fetch; ;; status) cmd_status; ;; log) cmd_log; ;;
    clear) cmd_clear; ;; test) cmd_test; ;; config) cmd_config; ;;
    update) cmd_update; ;; uninstall) cmd_uninstall; ;; help|--help|-h) cmd_help; ;;
    *) cmd_interactive; ;;
esac
