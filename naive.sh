#!/bin/bash

# 如果命令返回非零状态，立即退出
set -e

# 确保脚本以管理员权限运行
if [[ $EUID -ne 0 ]]; then
  echo "此脚本必须以root权限运行。请使用sudo或以root身份运行。"
  exit 1
fi

# 获取用户输入的域名
read -p "请输入您的已解析域名: " domain_name

# 确保用户输入的域名不为空
if [[ -z "$domain_name" ]]; then
  echo "域名不能为空。请重新运行脚本并输入有效的域名。"
  exit 1
fi

# 获取本机IP地址
local_ip=$(hostname -I | awk '{print $1}')

# 使用dig查询域名的A记录
resolved_ip=$(dig +short $domain_name | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}')

# 检查域名是否解析到本机IP地址
if [[ "$resolved_ip" != "$local_ip" ]]; then
  echo "域名未解析到本机IP地址 ($local_ip)。解析结果是: $resolved_ip"
  exit 1
fi

echo "域名成功解析到本机IP地址 ($local_ip)"


# 生成安全范围内的随机端口
random_http_port=$((1024 + RANDOM % (65535 - 1024)))
random_proxy_port=$((1024 + RANDOM % (65535 - 1024)))

echo "选择的HTTP端口: $random_http_port"
echo "选择的代理端口: $random_proxy_port"

# 生成随机用户名和密码
admin_user=$(tr -dc A-Za-z < /dev/urandom | head -c 6)
admin_pass=$(tr -dc A-Za-z < /dev/urandom | head -c 6)

echo "随机生成的用户: $admin_user"
echo "随机生成的密码: $admin_pass"

# 更新和升级系统包
echo "正在更新系统包"
if ! apt-get update && apt-get upgrade -y; then
  echo "系统包更新失败。请检查网络连接或包管理器。"
  exit 1
fi

# 安装Go语言
echo "正在安装Go"
if ! apt-get install -y software-properties-common; then
  echo "无法安装software-properties-common。请检查包管理器。"
  exit 1
fi

if ! add-apt-repository -y ppa:longsleep/golang-backports && apt-get update; then
  echo "无法添加Go的PPA。请检查网络连接。"
  exit 1
fi

if ! apt-get install -y golang-go; then
  echo "无法安装Go。请检查包管理器。"
  exit 1
fi

# 检查Go版本
go_version=$(go version)
if [[ -z "$go_version" ]]; then
  echo "Go安装失败。"
  exit 1
else
  echo "Go安装成功: $go_version"
fi

# 编译带有forwardproxy的Caddy服务器
echo "正在编译Caddy"
if ! go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest; then
  echo "无法安装xcaddy。"
  exit 1
fi

if ! ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive; then
  echo "无法编译带有forwardproxy的Caddy。"
  exit 1
fi

# 检查Caddy是否成功编译
if [[ ! -f /root/caddy ]]; then
  echo "Caddy编译失败，/root/caddy文件不存在"
  exit 1
fi

# 移动Caddy到/usr/bin/并确保具有执行权限
if ! mv /root/caddy /usr/bin/; then
  echo "无法将Caddy移动到/usr/bin/"
  exit 1
fi

if ! chmod +x /usr/bin/caddy; then
  echo "无法为Caddy设置执行权限"
  exit 1
else
  echo "Caddy成功移动到/usr/bin"
fi

# 创建并配置Caddyfile
echo "正在创建和配置Caddyfile"
if ! mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile; then
  echo "无法创建Caddyfile"
  exit 1
fi

cat <<EOF > /etc/caddy/Caddyfile
{
  http_port $random_http_port
}
:$random_proxy_port, $domain_name:$random_proxy_port
tls admin@outlook.com
route {
  forward_proxy {
    basic_auth $admin_user $admin_pass 
    hide_ip
    hide_via
    probe_resistance
  }
  reverse_proxy  https://www.jetbrains.com {
    header_up  Host  {upstream_hostport}
    header_up  X-Forwarded-Host  {host}
  }
}
EOF

# 格式化并验证Caddyfile
if ! caddy fmt --overwrite /etc/caddy/Caddyfile || ! caddy validate --config /etc/caddy/Caddyfile; then
  echo "Caddyfile格式或验证失败"
  exit 1
fi

# 创建systemd服务并配置Caddy服务
groupadd --system caddy
useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy

if ! touch /etc/systemd/system/caddy.service; then
  echo "无法创建caddy.service"
  exit 1
fi

cat <<EOF > /etc/systemd/system/caddy.service
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
EOF

# 启动并验证Caddy服务
if ! systemctl daemon-reload || ! systemctl enable caddy || ! systemctl start caddy; then
  echo "Caddy服务启动失败"
  exit 1
fi

if ! systemctl status caddy | grep "Active: active (running)"; then
  echo "Caddy服务未正确启动"
  exit 1
else
  echo "Caddy启动成功"
fi

# 输出Naiveproxy配置
echo "Naiveproxy配置"
cat <<EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://$admin_user:$admin_pass@$domain_name:$random_proxy_port"
}
EOF
