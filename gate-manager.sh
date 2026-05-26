#!/bin/bash
# Gate 代理网关管理脚本
# 命令: gate [restart|update|log|status|clear|uninstall|start|stop|config|test]

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

# 颜色输出函数
info() { echo -e "${BLUE}[Gate]${PLAIN} $1"; }
success() { echo -e "${GREEN}[Gate]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[Gate]${PLAIN} $1"; }
error() { echo -e "${RED}[Gate]${PLAIN} $1"; }

# 检查 root
check_root() {
    [[ $EUID -ne 0 ]] && error "请使用 root 用户运行！" && exit 1
}

# 检查核心
check_core() {
    if [[ ! -f "$CORE_BIN" ]]; then
        error "未检测到 Gate 核心，请先运行安装脚本！"
        error "bash <(curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh)"
        exit 1
    fi
}

# 获取节点 ID
get_node_id() {
    [[ -f "$CONF_FILE" ]] && grep "^node_id=" "$CONF_FILE" | cut -d= -f2
}

# 获取所有运行中的节点
get_running_nodes() {
    systemctl list-units --type=service --state=running "gate@*.service" --no-legend | grep -oP 'gate@\K[0-9]+'
}

# 启动所有节点
cmd_start() {
    check_core
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id，请先运行 'gate' 进行配置！"
        exit 1
    fi
    info "正在启动节点 ${nid}..."
    systemctl start "gate@${nid}"
    sleep 1
    if systemctl is-active --quiet "gate@${nid}"; then
        success "节点 ${nid} 启动成功！"
    else
        error "节点 ${nid} 启动失败，请查看日志：gate log"
    fi
}

# 停止所有节点
cmd_stop() {
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id！"
        exit 1
    fi
    info "正在停止节点 ${nid}..."
    systemctl stop "gate@${nid}"
    success "节点 ${nid} 已停止！"
}

# 重启节点
cmd_restart() {
    check_core
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id！"
        exit 1
    fi
    info "正在重启节点 ${nid}..."
    systemctl restart "gate@${nid}"
    sleep 2
    if systemctl is-active --quiet "gate@${nid}"; then
        success "节点 ${nid} 重启成功！"
    else
        error "节点 ${nid} 重启失败，请查看日志：gate log"
    fi
}

# 查看状态
cmd_status() {
    check_core
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        warn "未配置 node_id，显示所有节点状态..."
        systemctl list-units "gate@*.service" --no-legend
        return
    fi
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate 节点状态 - 节点 ${nid}${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    
    local status=$(systemctl is-active "gate@${nid}" 2>/dev/null)
    if [[ "$status" == "active" ]]; then
        echo -e "状态: ${GREEN}● 运行中${PLAIN}"
    else
        echo -e "状态: ${RED}● 已停止${PLAIN}"
    fi
    
    echo ""
    systemctl status "gate@${nid}" --no-pager -l 2>/dev/null | head -15
    
    echo ""
    echo -e "${BOLD}端口监听:${PLAIN}"
    local port=$(grep "listen_port" "$CONF_DIR/${nid}.json" 2>/dev/null | grep -oP '\d+')
    if [[ -n "$port" ]]; then
        ss -tlnp | grep "$port" || echo "  未监听到端口 ${port}"
    fi
}

# 查看日志
cmd_log() {
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id！"
        exit 1
    fi
    info "查看节点 ${nid} 日志 (Ctrl+C 退出)..."
    journalctl -u "gate@${nid}" -f --no-pager
}

# 查看最近日志
cmd_log_recent() {
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id！"
        exit 1
    fi
    info "节点 ${nid} 最近 50 条日志："
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    journalctl -u "gate@${nid}" --no-pager -n 50
}

# 清除日志
cmd_clear() {
    local nid=$(get_node_id)
    if [[ -z "$nid" ]]; then
        error "未配置 node_id！"
        exit 1
    fi
    info "正在清除节点 ${nid} 日志..."
    journalctl --rotate
    journalctl --vacuum-time=1s
    success "日志已清除！"
}

# 测试 API 对接
cmd_test() {
    check_core
    if [[ ! -f "$CONF_FILE" ]]; then
        error "配置文件不存在！"
        exit 1
    fi
    
    local api_mode=$(grep "^api=" "$CONF_FILE" | cut -d= -f2)
    local webapi_url=$(grep "^webapi_url=" "$CONF_FILE" | cut -d= -f2)
    local webapi_key=$(grep "^webapi_key=" "$CONF_FILE" | cut -d= -f2)
    local node_id=$(get_node_id)
    
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    echo -e "${BOLD}   Gate API 对接测试${PLAIN}"
    echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
    
    echo -e "对接模式: ${BOLD}${api_mode:-未设置}${PLAIN}"
    echo -e "节点 ID:   ${BOLD}${node_id:-未设置}${PLAIN}"
    echo ""
    
    if [[ "$api_mode" == "webapi" ]]; then
        echo -e "API 地址: ${webapi_url}"
        echo -e "API 密钥: ${webapi_key:0:10}..."
        echo ""
        
        # 测试 API 连通性
        info "测试 API 连通性..."
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$webapi_url" 2>/dev/null)
        if [[ "$http_code" == "200" ]]; then
            success "API 服务器可访问 (HTTP $http_code)"
        else
            error "API 服务器不可达 (HTTP $http_code)"
            return 1
        fi
        
        # 测试 Xboard API
        echo ""
        info "测试 Xboard API (/api/v1/server/NodeController/getNodeInfo)..."
        local response=$(curl -s --connect-timeout 5 \
            -H "Authorization: $webapi_key" \
            "$webapi_url/api/v1/server/NodeController/getNodeInfo?id=$node_id" 2>/dev/null)
        
        if echo "$response" | grep -q "code"; then
            success "Xboard API 响应成功！"
            echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
        else
            warn "Xboard API 无响应，尝试 V2board 路径..."
            
            # 测试 V2board API
            response=$(curl -s --connect-timeout 5 \
                "$webapi_url/mod_mu/nodes/$node_id/info?key=$webapi_key" 2>/dev/null)
            
            if echo "$response" | grep -q "code"; then
                success "V2board API 响应成功！"
                echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
            else
                error "所有 API 路径均无响应！"
                echo ""
                warn "请检查："
                echo "  1. 面板类型 (type) 是否正确 (xboard/v2board)"
                echo "  2. 节点 ID 是否与面板后台一致"
                echo "  3. WebAPI 密钥是否正确"
                echo "  4. 面板是否开启了节点通信功能"
                return 1
            fi
        fi
        
        # 测试用户列表获取
        echo ""
        info "测试获取用户列表..."
        if [[ "$api_mode" == "webapi" ]]; then
            # 尝试不同路径
            for path in \
                "/api/v1/server/NodeController/getUserList?id=$node_id" \
                "/mod_mu/users?key=$webapi_key&node_id=$node_id"; do
                response=$(curl -s --connect-timeout 5 "$webapi_url$path" 2>/dev/null)
                if echo "$response" | grep -q "code"; then
                    success "用户列表获取成功 ($path)"
                    echo "$response" | python3 -m json.tool 2>/dev/null | head -20
                    break
                fi
            done
        fi
    elif [[ "$api_mode" == "db" ]]; then
        info "数据库对接模式，跳过 API 测试"
    else
        warn "单机模式 (none)，无需对接面板"
    fi
    
    echo ""
    success "测试完成！"
}

# 编辑配置
cmd_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        error "配置文件不存在！"
        exit 1
    fi
    info "正在编辑配置文件..."
    ${EDITOR:-nano} "$CONF_FILE"
    success "配置已保存！"
    info "重启服务使配置生效：gate restart"
}

# 更新脚本
cmd_update() {
    check_core
    info "正在检查 Gate 更新..."
    
    # 备份当前脚本
    cp /usr/bin/gate /usr/bin/gate.bak.$(date +%Y%m%d)
    
    # 下载新版本
    if curl -Ls -o /usr/bin/gate "$SCRIPT_URL"; then
        chmod +x /usr/bin/gate
        success "Gate 管理脚本已更新！"
        info "正在重启服务..."
        cmd_restart
    else
        error "更新失败，请检查网络连接！"
        cp /usr/bin/gate.bak.* /usr/bin/gate 2>/dev/null
    fi
}

# 卸载
cmd_uninstall() {
    warn "确定要卸载 Gate 吗？此操作将删除所有配置！"
    read -p "输入 yes 确认卸载: " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "已取消卸载"
        return
    fi
    
    info "正在卸载 Gate..."
    
    # 停止所有节点
    for nid in $(systemctl list-units "gate@*.service" --no-legend | grep -oP 'gate@\K[0-9]+'); do
        systemctl stop "gate@${nid}" 2>/dev/null
        systemctl disable "gate@${nid}" 2>/dev/null
    done
    
    # 删除文件
    rm -f /usr/bin/gate
    rm -f /usr/local/bin/gate-core
    rm -f "$SYSTEMD_FILE"
    rm -rf "$CONF_DIR"
    
    # 重载 systemd
    systemctl daemon-reload
    systemctl reset-failed
    
    success "Gate 已完全卸载！"
}

# 显示帮助
cmd_help() {
    echo -e "${BOLD}Gate 代理网关管理工具${PLAIN}"
    echo ""
    echo -e "${BOLD}用法:${PLAIN}"
    echo "  gate              启动交互式管理面板"
    echo "  gate start        启动节点服务"
    echo "  gate stop         停止节点服务"
    echo "  gate restart      重启节点服务"
    echo "  gate status       查看节点状态"
    echo "  gate log          实时查看节点日志"
    echo "  gate log-recent   查看最近 50 条日志"
    echo "  gate clear        清除节点日志"
    echo "  gate test         测试面板 API 对接"
    echo "  gate config       编辑配置文件"
    echo "  gate update       更新 Gate 脚本"
    echo "  gate uninstall    完全卸载 Gate"
    echo "  gate help         显示此帮助信息"
    echo ""
    echo -e "${BOLD}版本:${PLAIN} Gate v1.0.0 (sing-box core)"
    echo -e "${BOLD}仓库:${PLAIN} https://github.com/997862/Gate"
}

# 交互式管理面板
cmd_interactive() {
    check_core
    
    while true; do
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo -e "${BOLD}        Gate 代理网关管理面板${PLAIN}"
        echo -e "${BOLD}═══════════════════════════════════════${PLAIN}"
        echo ""
        echo "  1. 查看节点状态"
        echo "  2. 重启节点服务"
        echo "  3. 查看实时日志"
        echo "  4. 编辑配置文件"
        echo "  5. 测试 API 对接"
        echo "  6. 更新 Gate"
        echo "  7. 清除日志"
        echo "  8. 完全卸载"
        echo "  0. 退出"
        echo ""
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1) cmd_status; ;;
            2) cmd_restart; ;;
            3) cmd_log; ;;
            4) cmd_config; ;;
            5) cmd_test; ;;
            6) cmd_update; ;;
            7) cmd_clear; ;;
            8) cmd_uninstall; exit 0; ;;
            0) exit 0; ;;
            *) warn "无效选择！" ;;
        esac
        
        echo ""
        read -p "按回车键继续..."
        clear
    done
}

# 主入口
case "${1:-}" in
    start) cmd_start; ;;
    stop) cmd_stop; ;;
    restart) cmd_restart; ;;
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
