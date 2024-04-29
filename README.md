# 安装 Go
安装必要的工具
```
apt-get install -y software-properties-common
```
添加 Golang 的 PPA
```
add-apt-repository -y ppa:longsleep/golang-backports
```
更新软件包列表
```
apt-get update
```
安装 Go
```
apt-get install -y golang-go
```
测试 Go
```
go version
```
# 使用 Go 编译 Caddy
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
```
```
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
```
# 创建 Caddyfile 文件并写入配置
```
touch Caddyfile
```
```
nano Caddyfile
```
```
:443, 已解析域名
tls admin@outlook.com
route {
 forward_proxy {
   basic_auth admin passeway 
   hide_ip
   hide_via
   probe_resistance
  }
 reverse_proxy  https://www.jetbrains.com  {
   header_up  Host  {upstream_hostport}
   header_up  X-Forwarded-Host  {host}
  }
}
```
使 Caddy 可执行并将 caddy 二进制文件移动到您的路径中，并将您的 Caddyfile 放在/etc/caddy/
```
chmod +x caddy
mv caddy /usr/bin/
```
```
mkdir /etc/caddy
mv Caddyfile /etc/caddy/
```
```
/usr/bin/caddy run --config /etc/caddy/Caddyfile
```
为 caddy 创建唯一的 Linux 组和用户
```
groupadd --system caddy

useradd --system \
    --gid caddy \
    --create-home \
    --home-dir /var/lib/caddy \
    --shell /usr/sbin/nologin \
    --comment "Caddy web server" \
    caddy
```
创建caddy.service
```
touch /etc/systemd/system/caddy.service
```
编辑caddy.service
```
nano /etc/systemd/system/caddy.service
```
```
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
```
# 使用 systemd 启动 caddy 服务
加载 systemd 服务
```
systemctl daemon-reload
```
自启 Caddy 服务
```
systemctl enable caddy
```
启动 Caddy 服务
```
systemctl start caddy
```
检查 Caddy 服务
```
systemctl status caddy
```
重启 caddy 服务
```
systemctl reload caddy
```
停止 Caddy 服务
```
systemctl stop caddy
```




# JSON 格式的代理配置
```
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@example.com"
}
```
项目地址
https://github.com/klzgrad/naiveproxy/wiki/Run-Caddy-as-a-daemon
