#!/bin/bash
# Gate Manager
RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'
CONF_DIR="/etc/gate"
mkdir -p "$CONF_DIR"

check_bin() {
    command -v gate-core &>/dev/null || { echo -e "${RED}Gate core not installed! Run install.sh.${PLAIN}"; exit 1; }
}

show_menu() {
    clear
    check_bin
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e "   Gate Manager (Sing-box Core)"
    echo -e "${GREEN}========================================${PLAIN}"
    echo -e " 1. New Instance"
    echo -e " 2. List Instances"
    echo -e " 3. Manage Instance (Start/Stop)"
    echo -e " 4. View Config"
    echo -e " 5. View Logs"
    echo -e " 6. Update Gate"
    echo -e " 7. Uninstall"
    echo -e " 0. Exit"
    echo -e "${GREEN}========================================${PLAIN}"
    read -p "Select: " choice
    case $choice in
        1) new_instance ;;
        2) list_instances ;;
        3) manage_instance ;;
        4) view_config ;;
        5) view_log ;;
        6) update_gate ;;
        7) uninstall ;;
        0) exit ;;
        *) echo "Invalid" ;;
    esac
}

new_instance() {
    read -p "Instance Name: " name
    [[ -z "$name" ]] && return
    [[ -f "$CONF_DIR/$name.json" ]] && echo "Exists" && return

    echo "1. VMess  2. VLESS  3. Trojan  4. Shadowsocks  5. Hysteria2"
    read -p "Protocol: " proto
    
    port=$((10000 + RANDOM % 50000))
    uuid=$(cat /proc/sys/kernel/random/uuid)
    pass=$(openssl rand -hex 16)

    case $proto in
        1) # VMess
            cat > "$CONF_DIR/$name.json" << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "vmess",
    "listen": "::",
    "listen_port": $port,
    "users": [{ "uuid": "$uuid", "alterId": 0 }],
    "transport": { "type": "tcp" }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF
            echo "VMess Created. Port: $port, UUID: $uuid"
            ;;
        2) # VLESS
            cat > "$CONF_DIR/$name.json" << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "listen_port": $port,
    "users": [{ "uuid": "$uuid" }],
    "transport": { "type": "tcp" }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF
            echo "VLESS Created. Port: $port, UUID: $uuid"
            ;;
        3) # Trojan
            cat > "$CONF_DIR/$name.json" << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "trojan",
    "listen": "::",
    "listen_port": $port,
    "users": [{ "password": "$pass" }]
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF
            echo "Trojan Created. Port: $port, Pass: $pass"
            ;;
        4) # SS
            cat > "$CONF_DIR/$name.json" << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "shadowsocks",
    "listen": "::",
    "listen_port": $port,
    "method": "aes-256-gcm",
    "password": "$pass"
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF
            echo "SS Created. Port: $port, Pass: $pass"
            ;;
        5) # Hysteria2
            cat > "$CONF_DIR/$name.json" << EOF
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [{
    "type": "hysteria2",
    "listen": "::",
    "listen_port": $port,
    "users": [{ "password": "$pass" }]
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF
            echo "Hysteria2 Created. Port: $port, Pass: $pass"
            ;;
    esac
    
    systemctl enable gate@$name
    systemctl start gate@$name
    echo "Instance started."
}

list_instances() {
    echo "Active Instances:"
    for f in $CONF_DIR/*.json; do
        [[ -f "$f" ]] || continue
        n=$(basename "$f" .json)
        s=$(systemctl is-active gate@$n)
        echo -e "  $n: $s"
    done
    read -p "Enter to return..."
}

manage_instance() {
    list_instances
    read -p "Name: " name
    [[ ! -f "$CONF_DIR/$name.json" ]] && echo "Not found" && return
    echo "1. Start 2. Stop 3. Restart"
    read -p "Action: " act
    case $act in
        1) systemctl start gate@$name ;;
        2) systemctl stop gate@$name ;;
        3) systemctl restart gate@$name ;;
    esac
}

view_config() {
    read -p "Name: " name
    [[ -f "$CONF_DIR/$name.json" ]] && cat "$CONF_DIR/$name.json" || echo "Not found"
    read -p "Enter..."
}

view_log() {
    read -p "Name: " name
    systemctl status gate@$name -n 20 --no-pager
    read -p "Enter..."
}

update_gate() {
    curl -Ls https://raw.githubusercontent.com/997862/Gate/main/install.sh | bash
}

uninstall() {
    read -p "Uninstall? (y/n): " y
    [[ "$y" != "y" ]] && return
    systemctl stop gate@* 2>/dev/null
    rm -f /usr/bin/gate /usr/local/bin/gate-core /etc/systemd/system/gate@.service
    rm -rf /etc/gate
    echo "Uninstalled."
}

show_menu
