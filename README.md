# 使用 Go 编译 Caddy
安装 Go
```
apt-get install -y software-properties-common && \
add-apt-repository -y ppa:longsleep/golang-backports && \
apt-get update && \
apt-get install -y golang-go && \
go version

```
编译 Caddy
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
chmod +x caddy && \
mv caddy /usr/bin/

```

# 创建 Caddyfile 文件并写入配置
```
mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile && nano /etc/caddy/Caddyfile
```
```
{
http_port 8880
}
:8080, example.com:8080
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
校验配置文件是否正确
```
caddy validate --config /etc/caddy/Caddyfile
```
格式化后覆盖原配置文件
```
caddy fmt --overwrite /etc/caddy/Caddyfile
```

输出当前 caddy 包含的模块
```
caddy list-modules && cd ~
```


创建caddy唯一的Linux 组和用户
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
touch /etc/systemd/system/caddy.service && nano /etc/systemd/system/caddy.service
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
加载 systemd
```
systemctl daemon-reload
```
自启 Caddy 
```
systemctl enable caddy
```
启动 Caddy 
```
systemctl start caddy
```
检查 Caddy 
```
systemctl status caddy
```
重启 caddy 
```
systemctl reload caddy
```
停止 Caddy 
```
systemctl stop caddy
```




# JSON 格式的代理配置
```
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@example.com:8080"
}
```
项目地址
https://github.com/klzgrad/naiveproxy/wiki/Run-Caddy-as-a-daemon
