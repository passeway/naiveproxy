#!/bin/bash

# 安装必要的工具
apt-get install -y software-properties-common

# 添加 Golang 的 PPA
add-apt-repository -y ppa:longsleep/golang-backports

# 更新软件包列表
apt-get update

# 安装 Go
apt-get install -y golang-go

# 使用 Go 编译 Caddy
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 询问用户输入域名
read -p "请输入您的域名: " DOMAIN

# 生成随机 5 位数的用户名和密码
USERNAME=$(shuf -zer -n5 {a..z} | tr -d '\0')
PASSWORD=$(shuf -zer -n5 {a..z} | tr -d '\0')

# 创建 Caddyfile 文件并写入配置
echo "443, $DOMAIN
tls admin@outlook.com
route {
  forward_proxy {
    basic_auth $USERNAME $PASSWORD
    hide_ip
    hide_via
    probe_resistance
  }
  reverse_proxy  https://demo.cloudreve.org  {
    header_up  Host  {upstream_hostport}
    header_up  X-Forwarded-Host  {host}
  }
}" > /etc/caddy/Caddyfile


# 重载 Caddy 配置
./caddy reload
echo "Caddy 配置已重载。"

# 在后台运行 Caddy
./caddy start
echo "Caddy 已在后台启动。"

# 确保 Caddy 已经成功启动
./caddy status
# 输出jsonp配置
echo "{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://$USERNAME:$PASSWORD@$DOMAIN"
}"
