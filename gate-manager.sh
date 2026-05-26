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
INSTALL_URL="https://raw.githubusercontent.com/997862/Gate/main/install.sh"
SYSTEMD_FILE="/etc/systemd/system/gate@.service"

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

cmd_start() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id，请先运行 'gate' 进行配置！" && exit 1
    # 自动拉取最新配置
    cmd_fetch_silent
    info "正在启动节点 ${nid}..."
    systemctl start "gate@${nid}"
    sleep 1
    systemctl is-active --quiet "gate@${nid}" && success "节点 ${nid} 启动成功！" || error "启动失败，请运行 'gate log' 查看日志"
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
    # 重启前先拉取最新配置（对齐 soga 行为）
    cmd_fetch_silent
    info "正在重启节点 ${nid}..."
    systemctl restart "gate@${nid}"
    sleep 2
    systemctl is-active --quiet "gate@${nid}" && success "节点 ${nid} 重启成功！" || error "重启失败，请运行 'gate log' 查看日志"
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
    
    echo ""
    echo -e "${BOLD}当前配置:${PLAIN}"
    if [[ -f "$CONF_DIR/${nid}.json" ]]; then
        local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONF_DIR/${nid}.json")
        local proto=$(grep -oP '"type":\s*"\K[^"]+' "$CONF_DIR/${nid}.json" | head -1)
        echo -e "协议: ${BOLD}${proto}${PLAIN} | 端口: ${BOLD}${port}${PLAIN}"
    else
        echo -e "${YELLOW}  未生成节点配置，请运行 'gate fetch' 从面板拉取${PLAIN}"
    fi
}

cmd_log() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    info "查看节点 ${nid} 日志 (Ctrl+C 退出)..."
    journalctl -u "gate@${nid}" -f --no-pager
}

cmd_log_recent() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    info "节点 ${nid} 最近 50 条日志："
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    journalctl -u "gate@${nid}" --no-pager -n 50
}

cmd_clear() {
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    info "正在清除节点 ${nid} 日志..."
    journalctl --rotate && journalctl --vacuum-time=1s
    success "日志已清除！"
}

# 从面板拉取配置并生成 JSON（核心功能，对齐 soga）
cmd_fetch() {
    check_core
    local api_mode=$(get_conf_val "api")
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    local node_id=$(get_node_id)
    
    [[ -z "$node_id" ]] && error "未配置 node_id！" && exit 1
    [[ "$api_mode" != "webapi" ]] && { warn "当前为 ${api_mode} 模式，跳过面板拉取"; return; }
    [[ -z "$webapi_url" || -z "$webapi_key" ]] && error "未配置 webapi_url 或 webapi_key！" && exit 1
    
    info "正在从面板拉取节点 ${node_id} 配置..."
    info "API: ${webapi_url}"
    
    # 尝试多种 API 路径（Xboard / V2board / 其他）
    local endpoints=(
        "/api/v1/server/UniProxy/getNodeInfo?id=${node_id}"
        "/api/v1/server/NodeController/getNodeInfo?id=${node_id}"
        "/api/v1/server/DeepbworkController/getNodeInfo?id=${node_id}"
        "/mod_mu/nodes/${node_id}/info?key=${webapi_key}"
        "/api/v1/server/config?node_id=${node_id}"
    )
    
    local response=""
    for ep in "${endpoints[@]}"; do
        response=$(curl -s --connect-timeout 10 "${webapi_url}${ep}" \
            -H "Authorization: ${webapi_key}" 2>/dev/null)
        if echo "$response" | grep -q '"code"'; then
            info "成功获取节点配置 (路径: ${ep})"
            break
        fi
        response=""
    done
    
    [[ -z "$response" ]] && error "无法从面板获取配置！请检查 API 地址、密钥、节点 ID 是否正确" && return 1
    
    # 解析响应并生成 sing-box JSON
    echo "$response" | python3 -c "
import json, sys

try:
    data = json.loads(sys.stdin.read())
except:
    print('ERROR: 无效的 JSON 响应')
    sys.exit(1)

# 适配不同面板的响应结构
node = data.get('data', data)
if isinstance(node, list) and len(node) > 0:
    node = node[0]

server_type = node.get('server_type', node.get('type', 'vmess')).lower()
listen_port = int(node.get('server_port', node.get('port', 443)))

# 提取用户
users = []
if server_type in ['vmess', 'vless']:
    for u in node.get('users', []):
        users.append({'uuid': u.get('uuid', '')})
    # 兼容旧版格式
    if 'uuid' in node:
        users.append({'uuid': node['uuid']})
elif server_type == 'trojan':
    for u in node.get('users', []):
        users.append({'password': u.get('password', '')})
elif server_type in ['shadowsocks', 'ss']:
    users.append({
        'password': node.get('password', ''),
        'method': node.get('cipher', '2022-blake3-aes-128-gcm')
    })

# 构建 sing-box 配置
config = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [{
        'type': server_type,
        'listen': '::',
        'listen_port': listen_port,
        'users': users if users else [{'uuid': '00000000-0000-0000-0000-000000000000'}]
    }],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}]
}

# 添加网络/传输配置
network = node.get('network', node.get('transport', 'tcp')).lower()
if network == 'ws':
    ws_path = node.get('ws_path', node.get('path', '/'))
    ws_host = node.get('ws_host', node.get('host', ''))
    config['inbounds'][0]['transport'] = {
        'type': 'ws',
        'path': ws_path,
        'headers': {'Host': ws_host} if ws_host else {}
    }
elif network == 'grpc':
    config['inbounds'][0]['transport'] = {
        'type': 'grpc',
        'service_name': node.get('grpc_service_name', node.get('serviceName', 'GunService'))
    }
elif network == 'h2':
    config['inbounds'][0]['transport'] = {
        'type': 'http',
        'host': node.get('h2_host', node.get('host', [])).split(',') if isinstance(node.get('h2_host'), str) else node.get('h2_host', []),
        'path': node.get('h2_path', node.get('path', '/'))
    }

# TLS 配置
tls = node.get('tls', False)
if tls or node.get('tls_settings'):
    config['inbounds'][0]['tls'] = {
        'enabled': True,
        'server_name': node.get('server_name', node.get('host', '')),
        'certificate_path': '/etc/gate/cert.pem',
        'key_path': '/etc/gate/key.pem'
    }

print(json.dumps(config, indent=2))
" 2>/dev/null > "$CONF_DIR/${node_id}.json"
    
    if [[ $? -eq 0 && -s "$CONF_DIR/${node_id}.json" ]]; then
        success "节点 ${node_id} 配置已生成！"
        echo -e "配置文件: ${CONF_DIR}/${node_id}.json"
        
        # 显示生成的配置摘要
        local port=$(grep -oP '"listen_port":\s*\K\d+' "$CONF_DIR/${node_id}.json")
        local proto=$(grep -oP '"type":\s*"\K[^"]+' "$CONF_DIR/${node_id}.json" | head -1)
        echo -e "协议: ${BOLD}${proto}${PLAIN} | 端口: ${BOLD}${port}${PLAIN} (来自面板)"
        echo ""
        info "重启服务使配置生效：gate restart"
    else
        error "配置生成失败！请检查面板返回格式"
        echo "原始响应: $response"
        return 1
    fi
}

# 静默拉取（用于 start/restart 时自动更新）
cmd_fetch_silent() {
    local api_mode=$(get_conf_val "api")
    [[ "$api_mode" != "webapi" ]] && return 0
    
    local response=$(curl -s --connect-timeout 5 \
        "${webapi_url}/api/v1/server/UniProxy/getNodeInfo?id=${node_id}" \
        -H "Authorization: ${webapi_key}" 2>/dev/null)
    
    if echo "$response" | grep -q '"code"'; then
        # 静默更新配置（同上逻辑，省略输出）
        echo "$response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    node = data.get('data', data)
    if isinstance(node, list) and len(node) > 0: node = node[0]
    server_type = node.get('server_type', node.get('type', 'vmess')).lower()
    listen_port = int(node.get('server_port', node.get('port', 443)))
    users = [{'uuid': u.get('uuid', '')} for u in node.get('users', [])]
    if not users and 'uuid' in node: users = [{'uuid': node['uuid']}]
    config = {'log': {'level': 'info', 'timestamp': True}, 'inbounds': [{'type': server_type, 'listen': '::', 'listen_port': listen_port, 'users': users if users else [{'uuid': '00000000-0000-0000-0000-000000000000'}]}], 'outbounds': [{'type': 'direct', 'tag': 'direct'}]}
    print(json.dumps(config, indent=2))
except: pass
" 2>/dev/null > "$CONF_DIR/${node_id}.json"
    fi
}

cmd_test() {
    check_core
    local api_mode=$(get_conf_val "api")
    local webapi_url=$(get_conf_val "webapi_url")
    local webapi_key=$(get_conf_val "webapi_key")
    local node_id=$(get_node_id)
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate API 对接测试${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "对接模式: ${BOLD}${api_mode:-未设置}${PLAIN}"
    echo -e "节点 ID:   ${BOLD}${node_id:-未设置}${PLAIN}"
    echo ""
    
    if [[ "$api_mode" == "webapi" ]]; then
        info "测试面板连通性..."
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$webapi_url" 2>/dev/null)
        [[ "$http_code" == "200" ]] && success "面板服务器可访问 (HTTP $http_code)" || error "面板服务器不可达 (HTTP $http_code)"
        
        echo ""
        info "尝试拉取节点配置..."
        cmd_fetch
    fi
}

cmd_config() {
    [[ ! -f "$CONF_FILE" ]] && error "配置文件不存在！" && exit 1
    info "正在编辑配置文件..."
    ${EDITOR:-nano} "$CONF_FILE"
    success "配置已保存！运行 'gate restart' 使配置生效"
}

cmd_update() {
    check_core
    info "正在检查 Gate 更新..."
    cp /usr/bin/gate /usr/bin/gate.bak.$(date +%Y%m%d)
    if curl -Ls -o /usr/bin/gate "$SCRIPT_URL"; then
        chmod +x /usr/bin/gate
        success "Gate 管理脚本已更新！"
        cmd_restart
    else
        error "更新失败！"
        cp /usr/bin/gate.bak.* /usr/bin/gate 2>/dev/null
    fi
}

cmd_uninstall() {
    warn "确定要卸载 Gate 吗？此操作将删除所有配置！"
    read -p "输入 yes 确认卸载: " confirm
    [[ "$confirm" != "yes" ]] && info "已取消卸载" && return
    
    info "正在卸载 Gate..."
    for nid in $(systemctl list-units "gate@*.service" --no-legend | grep -oP 'gate@\K[0-9]+'); do
        systemctl stop "gate@${nid}" 2>/dev/null; systemctl disable "gate@${nid}" 2>/dev/null
    done
    rm -f /usr/bin/gate /usr/local/bin/gate-core "$SYSTEMD_FILE"
    rm -rf "$CONF_DIR"
    systemctl daemon-reload && systemctl reset-failed
    success "Gate 已完全卸载！"
}

cmd_help() {
    echo -e "${BOLD}Gate 代理网关管理工具${PLAIN}"
    echo ""
    echo -e "${BOLD}用法:${PLAIN}"
    echo "  gate              启动交互式管理面板"
    echo "  gate fetch        从面板拉取节点配置 (端口/协议/用户)"
    echo "  gate start        启动节点 (自动拉取最新配置)"
    echo "  gate restart      重启节点 (自动拉取最新配置)"
    echo "  gate stop         停止节点"
    echo "  gate status       查看节点状态"
    echo "  gate log          实时查看节点日志"
    echo "  gate clear        清除节点日志"
    echo "  gate test         测试面板 API 对接"
    echo "  gate config       编辑配置文件"
    echo "  gate update       更新 Gate 脚本"
    echo "  gate uninstall    完全卸载 Gate"
    echo "  gate help         显示此帮助"
    echo ""
    echo -e "${BOLD}版本:${PLAIN} Gate v1.0.0 (sing-box core)"
}

cmd_interactive() {
    check_core
    while true; do
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo -e "${BOLD}        Gate 代理网关管理面板${PLAIN}"
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo ""
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
        echo ""
        read -p "请选择操作 [0-9]: " choice
        case $choice in
            1) cmd_fetch; ;;
            2) cmd_status; ;;
            3) cmd_restart; ;;
            4) cmd_log; ;;
            5) cmd_config; ;;
            6) cmd_test; ;;
            7) cmd_update; ;;
            8) cmd_clear; ;;
            9) cmd_uninstall; exit 0; ;;
            0) exit 0; ;;
            *) warn "无效选择！" ;;
        esac
        echo ""
        read -p "按回车键继续..."
        clear
    done
}

case "${1:-}" in
    start) cmd_start; ;;
    stop) cmd_stop; ;;
    restart) cmd_restart; ;;
    fetch) cmd_fetch; ;;
    status) cmd_status; ;;
    log) cmd_log; ;;
    log-recent) cmd_log_recent; ;;
    clear) cmd_clear; ;;
    test) cmd_test; ;;
    config) cmd_config; ;;
    update) cmd_update; ;;
    uninstall) cmd_uninstall; ;;
    help|--help|-h) cmd_help; ;;
    *) cmd_interactive; ;;
esac
