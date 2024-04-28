#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# Function to output colored text
red() {
    echo -e "${RED}$1${PLAIN}"
}

green() {
    echo -e "${GREEN}$1${PLAIN}"
}

yellow() {
    echo -e "${YELLOW}$1${PLAIN}"
}

# Check for root privileges
[[ $EUID -ne 0 ]] && red "请以root用户运行脚本" && exit 1

# Detect system and set package manager commands
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")

CMD=(
    "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d '\"' -f2)"
    "$(hostnamectl 2>/dev/null | grep -i system | cut -d ':' -f2)"
    "$(lsb_release -sd 2>/dev/null)"
    "$(grep . /etc/redhat-release 2>/dev/null)"
    "$(grep . /etc/issue 2>/dev/null | cut -d '\\' -f1 | sed '/^[ ]*$/d')"
)

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

SYSTEM=""
for ((i = 0; i < ${#REGEX[@]}; i++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[i]} ]] && SYSTEM="${REGEX[i]}" && break
done

[[ -z $SYSTEM ]] && red "不支持该操作系统" && exit 1

# Ensure curl is installed
if ! command -v curl &> /dev/null; then
    [[ ! $SYSTEM == "centos" ]] && ${PACKAGE_UPDATE[i]}
    ${PACKAGE_INSTALL[i]} curl
fi

# Detect CPU architecture
archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) red "不支持的CPU架构" && exit 1 ;;
    esac
}

# Function to install NaiveProxy
installProxy() {
    # Install dependencies and caddy
    [[ ! $SYSTEM == "centos" ]] && ${PACKAGE_UPDATE[i]}
    ${PACKAGE_INSTALL[i]} curl wget sudo qrencode

    rm -f /usr/bin/caddy
    wget "https://raw.githubusercontent.com/Misaka-blog/naiveproxy-script/main/files/caddy-linux-$(archAffix)" -O /usr/bin/caddy
    chmod +x /usr/bin/caddy

    mkdir /etc/caddy
    
    # Randomly assign ports and generate other required information
    proxyport=$(shuf -i 2000-65535 -n 1)
    caddyport=$(shuf -i 2000-65535 -n 1)
    
    yellow "NaiveProxy 的代理端口是：$proxyport"
    yellow "Caddy 监听端口是：$caddyport"

    domain="example.com"  # Default domain
    proxyname=$(date +%s%N | md5sum | cut -c 1-16)  # Random username
    proxypwd=$(date +%s%N | md5sum | cut -c 1-16)  # Random password

    # Default obfuscation site
    proxysite="demo.cloudreve.org"
    yellow "伪装站点为：https://$proxysite"

    # Create Caddy configuration
    cat <<EOF >/etc/caddy/Caddyfile
{
    http_port $caddyport
}
:$proxyport, $domain:$proxyport
tls admin@example.com
route {
    forward_proxy {
        basic_auth $proxyname $proxypwd
        hide_ip
        hide_via
        probe_resistance
    }
    reverse_proxy https://$proxysite {
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Host {host}
    }
}
EOF

    # Create client configuration
    mkdir -p /root/naive
    cat <<EOF > /root/naive/naive-client.json
{
    "listen": "socks://127.0.0.1:4080",
    "proxy": "https://${proxyname}:${proxypwd}@${domain}:${proxyport}",
    "log": ""
}
EOF
    
    # Create systemd service for Caddy
    cat <<EOF >/etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
ExecStart=/usr/bin/caddy run --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable caddy
    systemctl start caddy

    green "NaiveProxy 已成功安装并启动！"
}

# Function to uninstall NaiveProxy
uninstallProxy() {
    systemctl stop caddy
    rm -rf /etc/caddy
    rm -f /usr/bin/caddy
    green "NaiveProxy 已卸载"
}

# Menu to manage the script
menu() {
    clear
    echo -e "${GREEN}NaiveProxy 管理脚本${PLAIN}"
    echo -e "1. 安装 NaiveProxy"
    echo -e "2. 卸载 NaiveProxy"
    echo -e "3. 退出"

    read -rp "选择操作 [1-3]：" choice
    case $choice in
        1) installProxy ;;
        2) uninstallProxy ;;
        3) exit 0 ;;
        *) red "无效的选择" ;;
    esac
}

# Display the menu and handle user input
menu
