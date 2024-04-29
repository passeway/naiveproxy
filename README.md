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
使用以下内容创建：caddy.service
```
touch /etc/systemd/system/caddy.service
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
重新加载 systemd 的配置文件
```
systemctl daemon-reload
```
将 Caddy 服务设为开机自启
```
systemctl enable caddy
```
立即启动 Caddy 服务
```
systemctl start caddy
```
检查 Caddy 当前状态
```
systemctl status caddy
```
重新加载 caddy 配置文件
```
systemctl reload caddy
```


# JSON 格式的代理配置
```
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@example.com"
}
```
caddy配置守护进程（开机自启）：https://github.com/klzgrad/naiveproxy/wiki/Run-Caddy-as-a-daemon
