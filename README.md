<div align="center">

<h1>NaïveProxy</h1>

<p><strong>基于 Caddy 的代理部署与服务管理。</strong></p>

<p>从服务端安装到客户端配置，一个交互菜单完成。</p>

<p>
  <a href="https://github.com/passeway/naiveproxy/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/passeway/naiveproxy/build.yml?branch=main&amp;style=flat-square&amp;label=Build" alt="Build"></a>
  <img src="https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu-2563eb?style=flat-square" alt="Debian, Ubuntu">
  <img src="https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square" alt="AMD64, ARM64">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/passeway/naiveproxy?style=flat-square&amp;color=475569" alt="License"></a>
</p>

<p>
  <a href="#快速开始">快速开始</a> &nbsp;·&nbsp;
  <a href="#客户端配置">客户端配置</a> &nbsp;·&nbsp;
  <a href="#服务管理">服务管理</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/naiveproxy/releases">下载构建</a>
</p>

<br>

</div>

面向 Debian / Ubuntu 的 NaïveProxy 服务端部署脚本。使用集成 `forwardproxy-naive` 模块的 Caddy，通过 systemd 管理服务，并输出客户端分享链接与 JSON 配置。

- **预编译构建** — 从本仓库最新 Release 下载对应架构的 Caddy，部署时无需本机编译。
- **交互式安装** — 检查域名与端口，生成随机端口及认证信息，创建服务并配置开机自启。
- **统一管理** — 在同一菜单中启停、更新、卸载服务，以及查看安装时生成的连接信息。

## 快速开始

主脚本依赖 **apt-get 与 systemd**，适用于 **Debian / Ubuntu**，支持 **AMD64 / ARM64**。请使用 **root** 账户运行。

准备一个已直接解析到服务器公网地址的域名；使用 CDN DNS 服务时，设为仅 DNS 解析。终端需已安装 `bash`、`curl`、`ca-certificates` 和 `iproute2`。

```bash
bash <(curl -fsSL https://naiveproxy-sigma.vercel.app)
```

1. 选择 **1** 安装，按提示输入已解析的域名。
2. 在云安全组和服务器防火墙中放行生成的代理 **TCP 端口**，确认 TLS 证书签发成功。
3. 将输出的链接或 JSON 配置导入客户端。

> **安装前确认**
>
> 脚本会检查 TCP 80 / 443 占用；提示是否结束占用进程时，直接按 Enter 会默认确认并强制结束进程。已有网站时请选择 `n`，先处理端口冲突。脚本还会写入 `/usr/bin/caddy`、`/etc/caddy` 和 `caddy.service`，已有 Caddy 部署请先备份。

<details>
<summary>首次运行依赖与备用入口</summary>

安装命令依赖：

```bash
apt-get update &&
apt-get install -y bash curl ca-certificates iproute2
```

也可以直接下载主脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/naive.sh -o /tmp/naiveproxy-manager.sh &&
bash /tmp/naiveproxy-manager.sh
```

</details>

<details>
<summary>域名、端口与证书</summary>

代理连接使用脚本生成的端口；证书签发还需要正确的验证入口。

Caddy 的 HTTP-01 验证使用外部 TCP 80，TLS-ALPN-01 验证使用外部 TCP 443。脚本将 `http_port` 设为随机端口，且未自动添加端口转发规则；这不会改变证书机构访问的外部端口。若使用 HTTP-01，需要将外部 80 转发到实际 HTTP 监听端口，或调整 Caddy 配置使其监听 80。TLS-ALPN-01 则需确保外部 443 能到达相应验证监听端口。

服务进程运行不等于证书已签发。遇到 TLS 错误时，请检查域名解析、验证端口与 Caddy 日志。

参考：[Caddy 自动 HTTPS](https://caddyserver.com/docs/automatic-https#acme-challenges) · [`http_port` 说明](https://caddyserver.com/docs/caddyfile/options#http-port)。

</details>

## 客户端配置

安装完成后，脚本会显示连接信息，并保存到 `/etc/caddy/config.txt`。也可通过菜单 **6** 再次查看。

### 分享链接

使用支持 `naive+https` 链接的客户端导入：

```text
naive+https://USERNAME:PASSWORD@proxy.example.com:PORT#HK
```

节点标签来自公网 IP 的国家或地区查询结果。示例中的域名、端口和认证信息请替换为实际输出。

### NaïveProxy JSON

将 JSON 部分保存为客户端配置文件：

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://USERNAME:PASSWORD@proxy.example.com:PORT"
}
```

客户端启动后，本地 SOCKS 入口为 `127.0.0.1:1080`。客户端程序及使用方法参见 [NaïveProxy 上游项目](https://github.com/klzgrad/naiveproxy)。

`config.txt` 同时包含链接和 JSON，请按所需格式分别复制。手动修改服务端域名、端口或凭据后，也需更新客户端内容；菜单 **6** 只读取已保存的文件。

## 服务管理

再次运行安装命令即可进入菜单。服务名称为 **`caddy`**，运行账户为 **`caddy`**。

<details>
<summary>完整菜单</summary>

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 NaïveProxy 服务端 |
| `2` | 启动服务 |
| `3` | 停止服务 |
| `4` | 卸载服务及配置 |
| `5` | 下载本仓库最新 Release 的 Caddy 并重新启动 |
| `6` | 查看已保存的客户端连接信息 |
| `7` | 菜单显示“重启”，实际执行配置重载 |
| `0` | 退出 |

选项 **7** 调用 `systemctl reload caddy`。需要完整重启进程时，使用 `systemctl restart caddy`。

更新会先停止服务，再下载并启动，期间连接会中断。当前脚本未提供自动备份或失败回滚。卸载会删除程序、`/etc/caddy` 及服务文件，保留 `caddy` 用户和 `/var/lib/caddy` 下的数据。

</details>

<details>
<summary>文件位置与默认配置</summary>

| 路径 | 用途 |
| :--- | :--- |
| `/usr/bin/caddy` | 集成 NaïveProxy 模块的 Caddy |
| `/etc/caddy/Caddyfile` | 服务端配置 |
| `/etc/caddy/config.txt` | 安装时生成的链接与 JSON |
| `/etc/systemd/system/caddy.service` | systemd 服务定义 |
| `/var/lib/caddy` | Caddy 用户目录及运行数据 |

生成的配置启用 `basic_auth`、`hide_ip`、`hide_via` 与 `probe_resistance`，并配置到 `https://demo.cloudreve.org` 的反向代理。

TLS 联系邮箱由脚本随机生成，可在 Caddyfile 中替换为有效联系邮箱。仓库提供的 `index.html` 是独立静态页面，主脚本当前不会自动部署它。

</details>

<details>
<summary>配置校验、重载与状态检查</summary>

修改配置后，先校验，再重载：

```bash
caddy fmt --overwrite /etc/caddy/Caddyfile &&
caddy validate --config /etc/caddy/Caddyfile &&
systemctl reload caddy
```

查看运行状态、版本与日志：

```bash
systemctl status caddy --no-pager
caddy version
journalctl -u caddy -n 50 --no-pager
```

查看实时日志，按 `Ctrl+C` 结束：

```bash
journalctl -u caddy -f
```

</details>

## 构建与排障

本仓库通过 [GitHub Actions](https://github.com/passeway/naiveproxy/actions/workflows/build.yml) 手动触发构建，使用 xcaddy 编译 AMD64 / ARM64 版本，并发布到 [Releases](https://github.com/passeway/naiveproxy/releases)。安装脚本获取的是**本仓库最新发布的构建**，版本更新取决于发布进度。

<details>
<summary>从源码编译</summary>

准备好 Go 环境后，执行：

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest &&
"$(go env GOPATH)/bin/xcaddy" build \
  --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
```

命令在当前目录生成 `caddy`。检查版本与模块：

```bash
./caddy version
./caddy list-modules | grep forward_proxy
```

如需独立下载本仓库的预编译程序，可使用 [caddy.sh](caddy.sh)；该脚本会写入 `/usr/bin/caddy`，不负责创建服务端配置或 systemd 服务。

</details>

<details>
<summary>常见问题</summary>

- **提示域名解析不一致**：脚本比较 `getent hosts` 的首条结果与公网地址查询结果。检查 A / AAAA 记录及返回的地址族；多个解析记录或 CDN 代理可能导致比较不一致。
- **启动后仍无法连接**：检查实际代理端口、证书签发日志，以及客户端域名和凭据。
- **配置中提示不认识 `forward_proxy`**：确认使用包含对应模块的 Caddy，可通过 `caddy list-modules` 检查。
- **修改配置后客户端仍使用旧信息**：同步修改客户端配置；菜单 **6** 不会重新生成连接信息。
- **更新后服务未运行**：查看 `systemctl status caddy` 与 `journalctl -u caddy`；菜单的完成提示不能代替状态检查。

</details>

<details>
<summary>终端预览</summary>

![NaïveProxy 管理菜单示例](image.png)

</details>

通过 [Issues](https://github.com/passeway/naiveproxy/issues) 反馈问题时，请附上系统与架构、Caddy 版本、复现步骤及相关日志，并隐藏用户名、密码和完整节点链接。

---

<p align="center">
  基于 <a href="https://github.com/klzgrad/naiveproxy">NaïveProxy</a> 与 <a href="https://github.com/caddyserver/caddy">Caddy</a> · 独立部署与管理脚本<br>
  <a href="naive.sh">查看源码</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/naiveproxy/releases">下载构建</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/naiveproxy/issues">问题反馈</a>
</p>
