#!/bin/bash
# Gate Installer
RED='\033[0;31m'
GREEN='\033[0;32m'
PLAIN='\033[0m'

os_arch=""
if [[ $(uname -m) == "x86_64" ]]; then os_arch="amd64"
elif [[ $(uname -m) == "aarch64" ]]; then os_arch="arm64"
fi

if [[ -z "$os_arch" ]]; then
    echo "Unsupported arch"
    exit 1
fi

echo -e "${GREEN}Installing dependencies...${PLAIN}"
if [[ -f /etc/redhat-release ]]; then
    yum install -y wget curl jq cronie
elif [[ -f /etc/debian_version ]]; then
    apt update && apt install -y wget curl jq cron
fi

echo -e "${GREEN}Downloading sing-box...${PLAIN}"
version=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
version=${version#v}
echo "Version: $version"

url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${os_arch}.tar.gz"
wget --no-check-certificate -qO /tmp/sing-box.tar.gz "$url"

if [[ $? -ne 0 ]]; then
    echo "Download failed."
    exit 1
fi

tar -xzf /tmp/sing-box.tar.gz -C /tmp/
mv /tmp/sing-box-${version}-linux-${os_arch}/sing-box /usr/local/bin/gate-core
chmod +x /usr/local/bin/gate-core
rm -rf /tmp/sing-box*

echo -e "${GREEN}Installing Gate Manager...${PLAIN}"
wget --no-check-certificate -qO /usr/bin/gate https://raw.githubusercontent.com/997862/Gate/main/gate-manager.sh
chmod +x /usr/bin/gate

wget --no-check-certificate -qO /etc/systemd/system/gate@.service https://raw.githubusercontent.com/997862/Gate/main/gate@.service
systemctl daemon-reload

mkdir -p /etc/gate

echo -e "${GREEN}Installation Complete! Run 'gate' to manage.${PLAIN}"
gate
