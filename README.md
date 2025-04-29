## 终端预览
```mermaid
flowchart TD
    %% Distribution Layer
    subgraph "Distribution & Hosting"
        direction TB
        Vercel["Vercel CDN/Edge"]:::infra
        NaiveEntry["naive.sh (Installer Entry Point)"]:::shell
        Vercel -->|"fetch script"| NaiveEntry
    end

    %% CI/CD Layer
    subgraph "CI/CD Pipeline"
        direction TB
        GitHubRepo["GitHub Repository"]:::external
        WorkflowsDir[".github/workflows (CI Workflows Directory)"]:::external
        BuildYML["build.yml (CI/CD Pipeline Definition)"]:::external
        GitHubActions["GitHub Actions"]:::infra
        GitHubRepo -->|triggers CI| WorkflowsDir
        WorkflowsDir --> BuildYML
        BuildYML -->|executes| GitHubActions
    end

    %% Installer Scripts
    subgraph "Installer Scripts"
        direction TB
        GoInstall["go.sh (Go Toolchain Installer)"]:::shell
        XCaddyBuild["xcaddy build step"]:::binary
        CaddyBuild["caddy.sh (Caddy Build Script)"]:::shell
        NaiveEntry -->|calls| GoInstall
        NaiveEntry -->|invokes| XCaddyBuild
        XCaddyBuild -->|wrapped by| CaddyBuild
    end

    %% Installer Execution on Host
    subgraph "Host Installation"
        direction TB
        GoPPA["Go PPA / GitHub"]:::external
        USRCaddy["/usr/bin/caddy (Installed Binary)"]:::binary
        CaddyFile["/etc/caddy/Caddyfile"]:::service
        SystemdUnit["systemd Service Unit"]:::service
        NaiveEntry -->|calls| GoInstall
        GoInstall -->|install Go from| GoPPA
        CaddyBuild -->|installs binary| USRCaddy
        NaiveEntry -->|"write config"| CaddyFile
        NaiveEntry -->|"write unit"| SystemdUnit
        SystemdUnit -->|start service| USRCaddy
    end

    %% Runtime Components
    subgraph "Runtime"
        direction TB
        CaddyService["Caddy Web Server (forwardproxy)"]:::service
        ClientApps["Client Apps (e.g., Browsers, SOCKS5 Clients)"]:::external
        UpstreamProxy["Upstream HTTPS Proxy"]:::external
        USRCaddy -->|runs as| CaddyService
        ClientApps -->|connect SOCKS5| CaddyService
        CaddyService -->|forward to| UpstreamProxy
    end

    %% Documentation
    subgraph "Documentation & Config"
        direction TB
        Readme["README.md (Project Documentation & Usage Guide)"]:::external
        Vercel --> Readme
    end

    %% Click Events
    click NaiveEntry "https://github.com/passeway/naiveproxy/blob/main/naive.sh"
    click GoInstall "https://github.com/passeway/naiveproxy/blob/main/go.sh"
    click CaddyBuild "https://github.com/passeway/naiveproxy/blob/main/caddy.sh"
    click WorkflowsDir "https://github.com/passeway/naiveproxy/tree/main/.github/workflows"
    click BuildYML "https://github.com/passeway/naiveproxy/blob/main/.github/workflows/build.yml"
    click Vercel "https://github.com/passeway/naiveproxy/blob/main/vercel.json"
    click Readme "https://github.com/passeway/naiveproxy/blob/main/README.md"

    %% Styles
    classDef shell fill:#FFEB3B,stroke:#333,stroke-width:1px
    classDef binary fill:#03A9F4,stroke:#333,stroke-width:1px
    classDef service fill:#8BC34A,stroke:#333,stroke-width:1px
    classDef infra fill:#FF9800,stroke:#333,stroke-width:1px
    classDef external fill:#BDBDBD,stroke:#333,stroke-width:1px
```



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
source <(curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/go.sh)
```

卸载 Go 语言
```
sudo apt-get remove --purge -y golang-go && sudo apt-get autoremove -y && \
sudo apt-get remove --purge -y golang*
```
```
sudo rm -rf /usr/local/go && nano ~/.profile ## 删除export PATH=$PATH:/usr/local/go/bin
```

编译 Caddy 文件
```
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest && \
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive && \
chmod +x caddy && \
mv caddy /usr/bin/
```

查看 80/443 端口占用状态
```
sudo ss -tulnp | grep -E ':80|:443'
```
终止 80/443 端口占用进程
```
kill -9 PID
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

  reverse_proxy https://demo.cloudreve.org {
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
