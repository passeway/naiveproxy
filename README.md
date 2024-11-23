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
编译 Caddy 文件
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
chmod +x caddy && \
mv caddy /usr/bin/
```

创建 /var/www/html 目录
```
mkdir -p /var/www/html
```
下载文件到 /var/www/html
```
wget -O /var/www/html/index.html https://gitlab.com/passeway/naiveproxy/raw/main/index.html
```
创建 Caddyfile 配置文件
```
mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile && nano /etc/caddy/Caddyfile
```
```
{
    # 定义全局配置，例如 HTTP 端口
    http_port 8880
}

# 定义站点 block，监听 :8080 和 example.com:8080
:8080, example.com:8080 {
    # 使用 Let's Encrypt 自动生成 TLS 证书
    tls admin@gmail.com
    
    route {
        # 配置正向代理功能
        forward_proxy {
            basic_auth admin passeway # 设置代理的基本身份验证
            hide_ip                   # 隐藏真实 IP 地址
            hide_via                  # 隐藏 Via 头
            probe_resistance          # 启用探测防御
        }

        # 配置文件服务器
        file_server {
            root /var/www/html        # 指定文件服务器的根目录
        }
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
查看 Caddy 日志
```
journalctl -u caddy --no-pager
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

## NaïveProxy.json 格式的代理配置
```
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://admin:passeway@example.com:8080"
}
```

## 项目地址：https://github.com/klzgrad/naiveproxy
