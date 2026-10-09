<div align="center">

<h1>NaïveProxy</h1>

<p><strong>基于 Caddy 的代理部署与服务管理。</strong></p>

<p>Debian · Ubuntu · Alpine，从安装到维护，一个菜单完成。</p>

<p>
  <a href="https://github.com/passeway/naiveproxy/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/passeway/naiveproxy/check.yml?branch=main&amp;style=flat-square&amp;label=Checks" alt="Checks"></a>
  <a href="https://github.com/passeway/naiveproxy/actions/workflows/build.yml"><img src="https://img.shields.io/github/actions/workflow/status/passeway/naiveproxy/build.yml?branch=main&amp;style=flat-square&amp;label=Build" alt="Build"></a>
  <img src="https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=flat-square" alt="Debian, Ubuntu, Alpine">
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

使用集成 `forwardproxy-naive` 模块的 Caddy 部署 NaïveProxy 服务端。自动适配 systemd 与 OpenRC，下载本仓库的预编译程序，并生成客户端连接信息。

- **统一部署** — 安装所需依赖，生成随机凭据，配置 HTTPS 服务与开机自启。
- **校验与恢复** — 校验下载摘要、程序版本、模块和配置；替换后启动失败时尝试恢复原程序、配置与服务状态。
- **连接与维护** — 从当前服务端配置导出节点，在菜单中完成启停、更新、状态检查和日志查看。

## 快速开始

支持 **AMD64 / ARM64**，请使用 **root** 账户。准备一个直接解析到服务器公网地址的域名；使用 CDN DNS 服务时，设为仅 DNS 解析。

**Debian / Ubuntu · systemd**

终端需已安装 `bash`、`curl` 与 CA 证书。

```bash
bash <(curl -fsSL https://naiveproxy-sigma.vercel.app)
```

**Alpine · OpenRC**

首次运行先安装命令依赖：

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://naiveproxy-sigma.vercel.app)'
```

选择 **1** 安装，输入已解析的域名；证书联系邮箱可留空。其余运行依赖由脚本安装。

> **端口与证书**
>
> 新安装使用标准 HTTPS **443**，HTTP 验证入口保持 **80**。请在云安全组和防火墙中放行 TCP 80 / 443，并确认这些端口能从公网到达服务器。Caddy 启动后异步申请证书，进程运行不等于证书已签发，可通过菜单 **9** 查看进度。使用 HTTP/3 时还需放行 UDP 443。

安装前会检查 TCP 80 / 443 和 UDP 443 占用；发现冲突时退出，由你处理现有服务。脚本不会强制结束占用进程，也不会执行全系统软件包升级。

<details>
<summary>备用入口 · 直接从 GitHub 下载</summary>

在已安装 `bash`、`curl` 和 CA 证书的终端执行：

```sh
curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/naive.sh -o /tmp/naiveproxy-manager.sh &&
bash /tmp/naiveproxy-manager.sh
```

域名会校验格式，并检查 IPv4 / IPv6 解析。如果无法确认解析地址与检测到的公网地址匹配，会显示结果并询问是否继续；留空或输入 `n` 取消。

</details>

## 客户端配置

安装完成后显示连接信息，保存在 `/etc/caddy/config.txt`。菜单 **6** 会从**当前 Caddyfile** 重新读取域名、端口及认证信息后导出。

### 分享链接

使用支持 `naive+https` 链接的客户端导入：

```text
naive+https://USERNAME:PASSWORD@proxy.example.com#HK
```

默认 HTTPS 端口 `443` 在链接和 JSON 中省略；已有配置使用其他端口时，会保留实际端口。

新安装自动查询国家或地区代码作为节点名称，例如 `HK`、`US`；查询失败时使用 `Naive`。示例中的域名与凭据请替换为实际输出。

### NaïveProxy JSON

将 JSON 部分保存为客户端配置文件：

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://USERNAME:PASSWORD@proxy.example.com"
}
```

客户端启动后，本地 SOCKS 入口为 `127.0.0.1:1080`。客户端程序及使用方法参见 [NaïveProxy 上游项目](https://github.com/klzgrad/naiveproxy)。

`config.txt` 包含链接与 JSON，请按所需格式分别复制。自动导出面向单域名、单入站、单账户配置；无法唯一识别的自定义配置会报错，不会猜测连接参数。

## 服务管理

再次运行安装命令即可进入菜单。服务名称为 **`caddy`**，以 **`caddy`** 专用账户运行。菜单顶部显示安装状态、运行状态和程序版本。

常用操作：**5** 更新、**6** 导出节点、**7** 重启、**8** 状态、**9** 日志。

<details>
<summary>完整菜单</summary>

未安装时显示安装、卸载与退出；安装后显示完整菜单，保留原有选项编号。

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 NaïveProxy 服务端 |
| `2` | 校验配置并启动服务 |
| `3` | 停止服务 |
| `4` | 卸载程序及本项目配置，需输入 `y` 确认 |
| `5` | 更新 Caddy 内核 |
| `6` | 根据当前配置重新生成并查看节点 |
| `7` | 校验配置并重启进程 |
| `8` | 查看服务状态 |
| `9` | 查看实时日志，按 `Ctrl+C` 返回菜单 |
| `0` | 退出 |

菜单 **7** 现在执行真正的重启。修改配置后，先选择 **7**，再选择 **6** 重新导出客户端信息。

</details>

<details>
<summary>更新、旧版兼容与卸载</summary>

更新从本仓库最新稳定 Release 下载对应架构的程序，校验 GitHub 发布文件的 SHA-256 摘要，并检查版本、`forward_proxy` 模块和现有配置。预检查失败时，不停止正在运行的服务。

替换阶段暂存原程序与配置；文件写入、服务注册或启动失败时，尝试恢复原有文件及启用、运行状态。恢复失败会保留备份目录并显示其位置。成功后清理临时备份，不保留长期历史版本。依赖包、系统账户及 Caddy 运行数据不属于文件回滚范围。

可识别旧脚本的常见安装。选择 **5** 更新时保留原域名、端口、凭据与配置含义，包括旧版随机端口；不会自动迁移到 443。更新前原本停止的服务保持停止，原本未启用自启的服务保持该状态。

卸载删除本项目的程序、配置、服务定义和日志轮转任务，保留证书、站点、系统账户与日志。配置目录内的其他文件也会保留。

</details>

<details>
<summary>文件位置与默认配置</summary>

| 路径 | 用途 |
| :--- | :--- |
| `/usr/bin/caddy` | 集成 NaïveProxy 模块的 Caddy |
| `/etc/caddy/Caddyfile` | 服务端配置，权限 `root:caddy 640` |
| `/etc/caddy/config.txt` | 导出的链接与 JSON，权限 `root:root 600` |
| `/etc/caddy/naive-manager.json` | 管理标识、节点名称与默认首页摘要，权限 `root:root 600` |
| `/var/lib/caddy/naive-site/index.html` | 仓库首页部署位置 |
| `/etc/systemd/system/caddy.service` | Debian / Ubuntu 服务定义 |
| `/etc/init.d/caddy` | Alpine 服务定义 |
| `/var/log/caddy-naive.log` | Alpine 运行日志 |

新配置启用 `basic_auth`、`hide_ip`、`hide_via` 与 `probe_resistance`，并提供本地静态页面。新安装生成 16 位十六进制用户名和由 32 字节随机数据编码的密码。

新安装将仓库的 [index.html](index.html) 部署为静态首页，字体、背景与图标均内置，无第三方资源或统计请求。导航为页面内跳转，内容为静态介绍，不展示伪造的实时监控数据。

使用最新版脚本选择 **5** 更新时，会同步尚未自行修改的默认首页，并补齐缺失页面。脚本记录已部署页面的 SHA-256 摘要；当前文件与记录一致才自动更新，原样的旧 Welcome 页与上一版默认首页也可识别。内容相同时不重写文件，保留修改时间与缓存校验信息。

页面下载和检查在替换文件、重启服务之前完成。有可识别的默认首页时，下载失败会提示并保留原页，继续更新内核；缺失首页时则中止操作，保留原服务。摘要与页面一起参与失败回滚。

可以直接编辑 `/var/lib/caddy/naive-site/index.html` 定制内容，后续更新会保留自定义页面；旧版反向代理或自定义站点配置也保持不变。静态文件修改无需重启 Caddy。

Alpine 使用 `busybox-openrc` 提供定时服务，日志每小时检查一次，超过 1 MiB 时轮转，保留 3 份压缩归档；检查间隔内仍可能增长。程序通过 `cap_net_bind_service` 文件能力绑定低端口，实际运行账户仍为 `caddy`。

</details>

## 排障与验证

先检查配置，再查看对应系统的服务状态与日志。

```bash
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

<details>
<summary>Debian / Ubuntu · systemd</summary>

```bash
systemctl status caddy --no-pager
journalctl -u caddy -n 50 --no-pager
```

</details>

<details>
<summary>Alpine · OpenRC</summary>

```sh
rc-service caddy status
tail -n 50 /var/log/caddy-naive.log
getcap /usr/bin/caddy
```

若日志提示无法绑定低端口，检查 `getcap` 输出是否包含 `cap_net_bind_service=ep`，以及 VPS 是否允许该文件能力。程序更新时会重新设置此能力。

</details>

[自动检查](https://github.com/passeway/naiveproxy/actions/workflows/check.yml) 覆盖 Debian、Ubuntu 和 Alpine 容器中的依赖安装、脚本回归、真实 Caddy 配置与 HTTPS CONNECT 代理流量。静态首页另外检查 320–1440 px 布局、导航、键盘操作、减少动态效果偏好及无 JavaScript 浏览，并保留页面截图。服务生命周期通过模拟命令验证；容器检查不替代真实 VPS 的开机自启、公网证书签发与 ARM64 实机验证。

## 构建与发布

[构建工作流](https://github.com/passeway/naiveproxy/actions/workflows/build.yml) 手动触发，使用 xcaddy 编译 AMD64 / ARM64 程序，发布到 [Releases](https://github.com/passeway/naiveproxy/releases)。安装器获取的是**本仓库最新发布的构建**，更新进度取决于本仓库的发布。

<details>
<summary>从源码编译与独立下载</summary>

准备好 Go 环境后：

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest &&
"$(go env GOPATH)/bin/xcaddy" build \
  --with github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive
```

检查生成的程序：

```bash
./caddy version
./caddy list-modules | grep forward_proxy
```

[caddy.sh](caddy.sh) 保留独立下载入口，复用主脚本的下载与校验流程。它只安装程序；检测到已有 Caddy 服务时会拒绝替换，请改用管理菜单 **5**。

</details>

通过 [Issues](https://github.com/passeway/naiveproxy/issues) 反馈问题时，请附上系统与架构、Caddy 版本、复现步骤及相关日志，并隐藏用户名、密码和完整节点链接。

---

<p align="center">
  基于 <a href="https://github.com/klzgrad/naiveproxy">NaïveProxy</a> 与 <a href="https://github.com/caddyserver/caddy">Caddy</a> · 独立部署与管理脚本<br>
  <a href="naive.sh">查看源码</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/naiveproxy/releases">下载构建</a> &nbsp;·&nbsp;
  <a href="https://github.com/passeway/naiveproxy/issues">问题反馈</a>
</p>

