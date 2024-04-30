#!/bin/bash

# 让用户输入用于配置的域名
read -p "请输入域名 (例如 mydomain.com): " user_domain

# 第一步：安装 Go 语言
echo "正在安装 Go 语言..."
apt-get install -y software-properties-common && \
add-apt-repository -y ppa:longsleep/golang-backports && \
apt-get update && \
apt-get install -y golang-go && \
go version

# 第二步：编译 Caddy，添加前置代理模块
echo "正在编译 Caddy，并添加前置代理..."
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
chmod +x caddy && \
mv caddy /usr/bin/

# 第三步：创建和配置 Caddyfile
echo "正在配置 Caddy..."
mkdir -p /etc/caddy && \
touch /etc/caddy/Caddyfile

# 写入 Caddyfile 配置，并使用用户输入的域名
cat > /etc/caddy/Caddyfile <<EOL
{
  http_port 8880
}
:8080, $user_domain:8080
tls admin@outlook.com
route {
  forward_proxy {
    basic_auth admin passeway 
    hide_ip
    hide_via
    probe_resistance
  }
  reverse_proxy https://www.jetbrains.com {
    header_up Host {upstream_hostport}
    header_up X-Forwarded-Host {host}
  }
}
EOL

# 第四步：验证和格式化 Caddyfile
echo "正在验证和格式化 Caddyfile..."
cd /etc/caddy && \
caddy validate Caddyfile && \
caddy fmt --overwrite Caddyfile

# 第五步：创建 Caddy 的 systemd 服务
echo "正在创建 Caddy 的 systemd 服务..."
cat > /etc/systemd/system/caddy.service <<EOL
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOL

# 第六步：创建 Caddy 的系统用户和组
echo "正在创建 Caddy 的系统用户和组..."
groupadd --system caddy && \
useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy

# 第七步：重新加载 systemd，并启动 Caddy 服务
echo "正在启动 Caddy 服务..."
systemctl daemon-reload && \
systemctl enable caddy && \
systemctl start caddy

# 第八步：检查 Caddy 服务状态
echo "正在检查 Caddy 服务状态..."
systemctl status caddy

# 第九步：在终端中输出 JSON 格式的代理配置
echo "JSON 格式的代理配置如下:"
cat <<EOL
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@$user_domain:8080"
}
EOL

echo "脚本执行成功。"
