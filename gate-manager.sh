#!/bin/bash
# Gate 代理网关管理脚本
# 100% 开源源码，支持二开

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
# 核心功能：从面板拉取配置 (适配 Xboard UniProxy API)
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
    local node_config
    node_config=$(curl -s --connect-timeout 10 "${webapi_url}/api/v1/server/UniProxy/config?node_id=${node_id}&token=${webapi_key}" 2>/dev/null)
    
    if ! echo "$node_config" | grep -q '"server_port"'; then
        error "无法获取节点配置！请检查 API 地址、密钥、节点 ID 是否正确"
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
import json, os

node_conf = json.loads('${node_config}')
user_conf = json.loads('${user_list}')
port = node_conf.get('server_port', 443)
proto = node_conf.get('protocol', 'vmess').lower()
net = node_conf.get('network', 'tcp').lower()

users = [{'uuid': u['uuid']} for u in user_conf.get('users', [])]

cfg = {
    'log': {'level': 'info', 'timestamp': True},
    'inbounds': [{
        'type': proto,
        'listen': '::',
        'listen_port': port,
        'users': users if users else [{'uuid': '00000000-0000-0000-0000-000000000000'}]
    }],
    'outbounds': [{'type': 'direct', 'tag': 'direct'}]
}

# Network settings
if net == 'ws':
    cfg['inbounds'][0]['transport'] = {
        'type': 'ws',
        'path': node_conf.get('networkSettings', {}).get('path', '/')
    }
elif net == 'grpc':
    cfg['inbounds'][0]['transport'] = {
        'type': 'grpc',
        'service_name': node_conf.get('networkSettings', {}).get('serviceName', 'GunService')
    }

with open('${CONF_DIR}/${node_id}.json', 'w') as f:
    json.dump(cfg, f, indent=2)

print(f"SUCCESS: Port {port}, Proto {proto}, Users {len(users)}")
PYTHON_SCRIPT

    success "配置已生成！"
}

# 静默拉取 (用于后台任务)
cmd_fetch_silent() {
    cmd_fetch >/dev/null 2>&1
}

# ============================================================
# 常用命令
# ============================================================
cmd_start() {
    check_core
    local nid=$(get_node_id)
    [[ -z "$nid" ]] && error "未配置 node_id！" && exit 1
    
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
    journalctl -u "gate@${nid}" -p err -f --no-pager
}

cmd_clear() {
    info "正在清理日志..."
    journalctl --rotate
    journalctl --vacuum-time=30d
    success "已清理 30 天前的日志"
}

cmd_version() {
    echo -e "${BOLD}Gate Version:${PLAIN} v1.2.0"
    echo -e "${BOLD}Core Version:${PLAIN} $($CORE_BIN version | head -1)"
}

cmd_update() {
    info "正在检查更新..."
    if curl -Ls -o /usr/bin/gate "$SCRIPT_URL"; then
        chmod +x /usr/bin/gate
        success "Gate 脚本已更新！请运行 'gate restart' 使配置生效"
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
# 高级功能：内存监控 & 自动维护
# ============================================================
cmd_monitor_setup() {
    local action=$1
    
    # 获取阈值配置 (默认 80%)
    local threshold=$(get_conf_val "mem_threshold")
    threshold=${threshold:-80}
    
    # 创建监控脚本
    local monitor_script="/etc/gate/gate-monitor.sh"
    mkdir -p /etc/gate
    
    cat > "$monitor_script" << 'MEOF'
#!/bin/bash
# Gate 自动监控脚本
CONF_FILE="/etc/gate/gate.conf"
CORE_BIN="/usr/local/bin/gate-core"
NODE_ID=$(grep "^node_id=" $CONF_FILE 2>/dev/null | cut -d= -f2)
THRESHOLD=$(grep "^mem_threshold=" $CONF_FILE 2>/dev/null | cut -d= -f2)
THRESHOLD=${THRESHOLD:-80}

# 1. 内存监控与释放
usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')
if [ "$usage" -gt "$THRESHOLD" ]; then
    # 清理缓存
    sync; echo 3 > /proc/sys/vm/drop_caches
    # 重启服务以释放内存
    systemctl restart gate@$NODE_ID
    echo "$(date) - Mem usage ${usage}% > ${THRESHOLD}%, restarted gate service" >> /var/log/gate-monitor.log
fi

# 2. 自动清理旧日志 (每天执行一次，通过 crontab 控制频率)
journalctl --vacuum-time=30d

# 3. 自动检测更新 (每 7 天执行一次)
SCRIPT_URL="https://raw.githubusercontent.com/997862/Gate/main/gate-manager.sh"
if [ ! -f /etc/gate/last_check_update ] || [ $(($(date +%s) - $(stat -c %Y /etc/gate/last_check_update 2>/dev/null || echo 0))) -gt 604800 ]; then
    curl -Ls -o /tmp/gate-check.sh "$SCRIPT_URL" 2>/dev/null
    if diff /usr/bin/gate /tmp/gate-check.sh >/dev/null 2>&1; then
        echo "$(date) - Gate is up to date" >> /var/log/gate-monitor.log
    else
        echo "$(date) - Gate update available! Run 'gate update'" >> /var/log/gate-monitor.log
    fi
    rm -f /tmp/gate-check.sh
    touch /etc/gate/last_check_update
fi
MEOF
    chmod +x "$monitor_script"
    
    if [[ "$action" == "start" ]]; then
        # 添加 crontab: 每 5 分钟检查一次内存和日志，每 7 天检查更新
        (crontab -l 2>/dev/null; echo "*/5 * * * * $monitor_script") | crontab -
        success "内存监控已开启 (阈值: ${threshold}%)"
        info "每 5 分钟检查一次，自动清理 30 天前日志，每周检查更新"
    elif [[ "$action" == "stop" ]]; then
        crontab -l 2>/dev/null | grep -v 'gate-monitor' | crontab -
        success "内存监控已关闭"
    fi
}

cmd_monitor_status() {
    if crontab -l 2>/dev/null | grep -q 'gate-monitor'; then
        success "监控运行中"
    else
        warn "监控未开启"
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
        success "面板通信正常！"
        cmd_fetch
    else
        error "面板通信失败！"
    fi
}

cmd_help() {
    echo -e "${BOLD}Gate 代理网关管理工具 v1.2.0${PLAIN}"
    echo ""
    echo "  gate fetch        从面板拉取节点配置"
    echo "  gate start        启动服务 (自动拉取 + 开机自启)"
    echo "  gate restart      重启服务 (自动拉取)"
    echo "  gate stop         停止服务"
    echo "  gate status       查看运行状态"
    echo "  gate info         查看节点详细信息"
    echo "  gate log          实时滚动日志"
    echo "  gate error        仅查看错误日志"
    echo "  gate -v           查看版本信息"
    echo "  gate test         测试面板连通性"
    echo "  gate update       更新 Gate 脚本"
    echo "  gate monitor start 开启内存监控 (默认 80% 重启)"
    echo "  gate monitor stop  关闭内存监控"
    echo "  gate clear        手动清理日志"
    echo "  gate uninstall    卸载"
}

cmd_interactive() {
    check_core
    while true; do
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo -e "${BOLD}        Gate 代理网关管理面板${PLAIN}"
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo "  1. 查看节点信息 (info)"
        echo "  2. 启动服务 (start)"
        echo "  3. 重启服务 (restart)"
        echo "  4. 查看实时日志 (log)"
        echo "  5. 开启/关闭监控 (monitor)"
        echo "  6. 更新 Gate (update)"
        echo "  7. 完全卸载 (uninstall)"
        echo "  0. 退出"
        read -p "请选择 [0-7]: " choice
        case $choice in
            1) cmd_info; ;; 2) cmd_start; ;; 3) cmd_restart; ;; 4) cmd_log; ;;
            5) read -p "开启(y)/关闭(n)? " ans; [[ "$ans" == "y" ]] && cmd_monitor_setup start || cmd_monitor_setup stop; ;;
            6) cmd_update; ;; 7) cmd_uninstall; exit 0; ;; 0) exit 0; ;; *) warn "无效选择"; ;;
        esac
        read -p "按回车键继续..."
        clear
    done
}

case "${1:-}" in
    start) cmd_start; ;; stop) cmd_stop; ;; restart) cmd_restart; ;;
    fetch) cmd_fetch; ;; status) cmd_status; ;; info) cmd_info; ;;
    log) cmd_log; ;; error) cmd_error; ;; clear) cmd_clear; ;;
    test) cmd_test; ;; update) cmd_update; ;; uninstall) cmd_uninstall; ;;
    monitor) cmd_monitor_setup "${2:-status}"; ;;
    -v|--version) cmd_version; ;; help|--help|-h) cmd_help; ;;
    *) cmd_interactive; ;;
esac
