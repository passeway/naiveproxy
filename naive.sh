#!/bin/bash

# 安装必要的工具
apt-get install -y software-properties-common

# 添加 Golang 的 PPA
add-apt-repository -y ppa:longsleep/golang-backports

# 更新软件包列表
apt-get update

# 安装 Go
apt-get install -y golang-go

# 测试 Go
go version

# 使用 Go 编译 Caddy
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

# 创建 Caddyfile 文件并写入配置

touch Caddyfile

:443, 已解析域名
tls admin@outlook.com
route {
 forward_proxy {
   basic_auth admin passeway 
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://demo.cloudreve.org  {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}

# caddy常用指令：
前台运行caddy：./caddy run

后台运行caddy：./caddy start

停止caddy：./caddy stop

重载配置：./caddy reload

# 输出 JSON 格式的代理配置
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@example.com"
}

caddy配置守护进程（开机自启）：https://github.com/klzgrad/naiveproxy/wiki/Run-Caddy-as-a-daemon
