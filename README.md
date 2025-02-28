## 终端预览

![preview](image.png)
## 一键脚本
```
bash <(curl -fsSL naiveproxy-sigma.vercel.app)
```

## 安装 NaïveProxy
安装 Go 语言
```
apt-get install -y software-properties-common && \
add-apt-repository -y ppa:longsleep/golang-backports && \
apt-get update && \
apt-get install -y golang-go && \
go version
```
```
source <(curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/Go.sh)
```
编译 Caddy 文件
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
chmod +x caddy && \
mv caddy /usr/bin/
```

查看80 443 端口是否占用
```
sudo ss -tuln | grep -E ':80|:443'
```
创建 Caddyfile 配置文件
```
mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile && nano /etc/caddy/Caddyfile
```
```
:443, example.com
tls me@example.com
route {
  forward_proxy {
    basic_auth user pass
    hide_ip
    hide_via
    probe_resistance
  }
 reverse_proxy https://bing.com {
    header_up Host {upstream_hostport}
  }
}
```
格式化 Caddyfile 覆盖原配置文件
```
caddy fmt --overwrite /etc/caddy/Caddyfile
```
校验 Caddyfile 配置是否正确
```
caddy validate --config /etc/caddy/Caddyfile
```
创建 Caddy 的Linux 组和用户
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
创建 Caddy 服务的 Systemd 配置
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
启动 Naive 服务
```
systemctl daemon-reload && \
systemctl enable caddy && \
systemctl start caddy && \
systemctl status caddy
```
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
检查 Caddy 状态
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
查看 Caddy 版本
```
caddy version
```
查看 Caddy 日志
```
journalctl -u caddy --no-pager
```
压缩 Caddy 内核
```
tar -cvzf caddy-arm64-v2.9.1.tar.gz -C /usr/bin caddy
```
解压 Caddy 内核
```
tar -xvzf caddy-arm64-v2.9.1.tar.gz -C /usr/bin
```
重载 Caddy 配置
```
caddy reload --config /etc/caddy/Caddyfile
```
运行 Caddy 服务
```
/usr/bin/caddy run --config /etc/caddy/Caddyfile
```

查看 Caddy 证书
```
ls -a /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```
## 卸载 NaïveProxy
```
systemctl stop caddy && \
systemctl disable caddy && \
rm /usr/bin/caddy && \
rm -rf /etc/caddy && \
rm -rf /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/* && \
rm /etc/systemd/system/caddy.service && \
systemctl daemon-reload && \
rm ~/go/bin/xcaddy
```
停止 Caddy 服务
```
systemctl stop caddy
```
禁用 Caddy 服务
```
systemctl disable caddy
```
删除 Caddy 文件
```
rm /usr/bin/caddy
rm -rf /etc/caddy
rm -rf /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/*
```
删除 systemd 服务
```
rm /etc/systemd/system/caddy.service
systemctl daemon-reload
```
删除 xcaddy 文件
```
rm ~/go/bin/xcaddy
```

## NaïveProxy.json
```
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://user:pass@example.com"
}
```

## 项目地址：https://github.com/klzgrad/naiveproxy
