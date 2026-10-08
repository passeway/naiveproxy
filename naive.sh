#!/usr/bin/env bash
# NaiveProxy server manager: Debian/Ubuntu (systemd), Alpine (OpenRC).
BINARY=/usr/bin/caddy
CONFIG_DIR=/etc/caddy
CONFIG_FILE=$CONFIG_DIR/Caddyfile
CLIENT_FILE=$CONFIG_DIR/config.txt
META_FILE=$CONFIG_DIR/naive-manager.json
DATA_DIR=/var/lib/caddy
LOCK_FILE=/run/lock/naiveproxy-manager.lock
LOG_FILE=/var/log/caddy-naive.log
CRON_FILE=/etc/periodic/hourly/naiveproxy-logrotate
ROTATE_STATE=/var/lib/logrotate/naiveproxy.status
RELEASE_API=https://api.github.com/repos/passeway/naiveproxy/releases/latest
SITE_URL=https://raw.githubusercontent.com/passeway/naiveproxy/main/index.html

fail() { printf '错误：%s\n' "$*" >&2; return 1; }
get_system_type() {
    local ID=''
    [ -r /etc/os-release ] && . /etc/os-release
    case "$ID" in debian|ubuntu|alpine) echo "$ID";; *) return 1;; esac
}
get_architecture() {
    case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) fail '仅支持 AMD64 / ARM64';; esac
}
service_file() {
    if [ "$(get_system_type)" = alpine ]; then echo /etc/init.d/caddy
    else echo /etc/systemd/system/caddy.service; fi
}
service_action() {
    # Never leak the operation lock into a daemon or its supervisor.
    if [ "$(get_system_type)" = alpine ]; then rc-service caddy "$@" 9>&-
    else systemctl "$@" caddy.service 9>&-; fi
}
is_running() {
    if [ "$(get_system_type)" = alpine ]; then service_action status >/dev/null 2>&1
    else systemctl is-active --quiet caddy.service 9>&-; fi
}
is_enabled() {
    if [ "$(get_system_type)" = alpine ]; then [ -L /etc/runlevels/default/caddy ]
    else systemctl is-enabled --quiet caddy.service 9>&-; fi
}
enable_service() {
    if [ "$(get_system_type)" = alpine ]; then rc-update add caddy default 9>&-
    else systemctl enable caddy.service 9>&-; fi
}
disable_service() {
    if [ "$(get_system_type)" = alpine ]; then
        if is_enabled; then rc-update del caddy default 9>&-; fi
    else systemctl disable caddy.service 9>&-; fi
}
reload_manager() { [ "$(get_system_type)" = alpine ] || systemctl daemon-reload 9>&-; }
is_installed() { [ -x "$BINARY" ] && [ -f "$CONFIG_FILE" ]; }
is_managed() {
    if [ -f "$META_FILE" ] && grep -q '"project": "passeway/naiveproxy"' "$META_FILE"; then return 0; fi
    # Recognize the old installer without claiming arbitrary Caddy deployments.
    [ -f "$CONFIG_FILE" ] && [ -f "$CLIENT_FILE" ] && [ -f "$(service_file)" ] &&
        grep -q '^naive+https://' "$CLIENT_FILE" && grep -q 'forward_proxy' "$CONFIG_FILE" &&
        grep -Fq "$BINARY run" "$(service_file)" && grep -Fq "$CONFIG_FILE" "$(service_file)"
}
require_managed() { is_installed && is_managed || { fail '未检测到本项目安装；请先安装，或检查是否为其他 Caddy 服务'; return 1; }; }
install_dependencies() {
    case "$(get_system_type)" in
        debian|ubuntu)
            apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y bash curl ca-certificates python3 iproute2 util-linux || return 1;;
        alpine)
            apk add --no-cache bash curl ca-certificates python3 iproute2 openrc busybox-openrc flock libcap logrotate gcompat libstdc++ || return 1;;
        *) fail '仅支持 Debian、Ubuntu、Alpine'; return 1;;
    esac
}
ensure_lock_tool() {
    command -v flock >/dev/null 2>&1 && return 0
    if [ "$(get_system_type)" = alpine ]; then apk add --no-cache flock
    else apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y util-linux; fi
}
with_lock() (
    umask 077
    mkdir -p "$(dirname "$LOCK_FILE")" || return 1
    exec 9>"$LOCK_FILE" || return 1
    flock -n 9 || { fail '已有 NaïveProxy 管理操作正在运行'; return 1; }
    "$@"
)
write_file() (
    local destination="$1" mode="$2" owner="$3" temporary
    [ ! -L "$destination" ] || { fail "拒绝覆盖符号链接：$destination"; return 1; }
    temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM HUP
    cat > "$temporary" && chown "$owner" "$temporary" && chmod "$mode" "$temporary" && mv -f "$temporary" "$destination"
)

# Parsing, cryptographic randomness and URI escaping stay out of shell substitutions.
data_tool() {
    python3 - "$@" <<'PY'
import base64, hashlib, ipaddress, json, os, re, secrets, shutil, socket, sys, tarfile
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

def write(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    os.chmod(path, 0o600)
def domain(value):
    value=value.lower().rstrip('.')
    if len(value)>253 or '.' not in value: raise ValueError('请输入完整域名')
    try: ipaddress.ip_address(value)
    except ValueError: pass
    else: raise ValueError('请使用域名，而非 IP 地址')
    if not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x) for x in value.split('.')):
        raise ValueError('域名格式无效；国际化域名请使用 punycode')
    return value
def walk(obj):
    if isinstance(obj,dict):
        yield obj
        for value in obj.values(): yield from walk(value)
    elif isinstance(obj,list):
        for value in obj: yield from walk(value)
def connection(config):
    matches=[]
    for server in config.get('apps',{}).get('http',{}).get('servers',{}).values():
        handlers=[x for x in walk(server.get('routes',[])) if x.get('handler')=='forward_proxy']
        for handler in handlers: matches.append((server,handler))
    if len(matches)!=1: raise ValueError('需要唯一的 forward_proxy 入站才能自动导出')
    server,handler=matches[0]
    ports={int(x.rsplit(':',1)[1]) for x in server.get('listen',[])}
    if len(ports)!=1 or not 1<=next(iter(ports))<=65535: raise ValueError('无法确定唯一代理端口')
    tls=config.get('apps',{}).get('tls',{})
    names=set(tls.get('certificates',{}).get('automate',[]))
    for policy in tls.get('automation',{}).get('policies',[]): names.update(policy.get('subjects',[]))
    for item in walk(server.get('routes',[])): names.update(item.get('host',[]))
    if len(names)!=1: raise ValueError('无法确定唯一域名；请检查自定义站点配置')
    creds=handler.get('auth_credentials',[])
    if len(creds)!=1: raise ValueError('需要唯一的认证账户才能自动导出')
    # Caddy's [][]byte JSON representation wraps the Basic Auth token twice.
    decoded=base64.b64decode(base64.b64decode(creds[0],validate=True),validate=True).decode()
    user,sep,password=decoded.partition(':')
    if not sep or not user or not password: raise ValueError('认证信息无效')
    return dict(domain=domain(next(iter(names))),port=next(iter(ports)),user=user,password=password)
try:
    action,*args=sys.argv[1:]
    if action=='release':
        release=json.loads(Path(args[0]).read_text()); arch=args[1]
        tag=release.get('tag_name','')
        if release.get('draft') is not False or release.get('prerelease') is not False or not re.fullmatch(r'v\d+\.\d+\.\d+',tag):
            raise ValueError('Release 不是有效的稳定版本')
        name=f'caddy_{tag[1:]}_linux_{arch}.tar.gz'
        url=f'https://github.com/passeway/naiveproxy/releases/download/{tag}/{name}'
        assets=[a for a in release.get('assets',[]) if a.get('name')==name and a.get('browser_download_url')==url]
        if len(assets)!=1: raise ValueError('缺少当前架构的发布文件')
        digest=assets[0].get('digest','')
        if not re.fullmatch(r'sha256:[0-9a-f]{64}',digest or ''): raise ValueError('发布文件缺少 SHA-256 摘要')
        print(tag+'\t'+url+'\t'+digest[7:])
    elif action=='extract':
        archive,digest,target=args
        checksum=hashlib.sha256()
        with open(archive,'rb') as f:
            for block in iter(lambda:f.read(1024*1024),b''): checksum.update(block)
        if checksum.hexdigest()!=digest: raise ValueError('安装包 SHA-256 校验失败')
        with tarfile.open(archive,'r:gz') as tar:
            members=[m for m in tar.getmembers() if m.name in ('caddy','./caddy')]
            if len(members)!=1 or not members[0].isfile() or members[0].size>200*1024*1024:
                raise ValueError('安装包中的 Caddy 文件无效')
            with tar.extractfile(members[0]) as source,open(target,'wb') as destination: shutil.copyfileobj(source,destination)
        os.chmod(target,0o755)
    elif action=='domain': print(domain(args[0]))
    elif action=='dns':
        names=sorted({x[4][0] for x in socket.getaddrinfo(domain(args[0]),443,type=socket.SOCK_STREAM)})
        if not names: raise ValueError('域名无解析记录')
        print('\n'.join(names))
    elif action=='ip': print(ipaddress.ip_address(args[0]))
    elif action=='new':
        directory,host,email,site=args;host=domain(host)
        if email and not re.fullmatch(r'[A-Za-z0-9._+%\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',email):
            raise ValueError('邮箱格式无效，可留空使用默认 ACME 设置')
        username=secrets.token_hex(8);password=secrets.token_urlsafe(32)
        tls='\n\ttls '+email if email else ''
        Path(directory,'Caddyfile').write_text(
            '{\n\torder forward_proxy before file_server\n\tlog {\n\t\texclude http.log.error\n\t}\n}\n'
            f':443, {host} {{{tls}\n\tencode gzip\n\tforward_proxy {{\n'
            f'\t\tbasic_auth {username} {password}\n\t\thide_ip\n\t\thide_via\n\t\tprobe_resistance\n\t}}\n'
            f'\tfile_server {{\n\t\troot {json.dumps(site)}\n\t}}\n}}\n')
    elif action=='export':
        adapted,metadata,previous,name,target=args
        info=connection(json.loads(Path(adapted).read_text()))
        if Path(metadata).is_file(): name=json.loads(Path(metadata).read_text()).get('name',name)
        elif Path(previous).is_file():
            for line in Path(previous).read_text().splitlines():
                if line.startswith('naive+https://'): name=unquote(urlsplit(line).fragment) or name;break
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,40}',name): name='Naive'
        auth=quote(info['user'],safe='')+':'+quote(info['password'],safe='')
        authority=f"{auth}@{info['domain']}"
        if info['port']!=443: authority+=f":{info['port']}"
        value='naive+https://'+authority+'#'+quote(name,safe='')+'\n\n'
        value+=json.dumps({'listen':'socks://127.0.0.1:1080','proxy':'https://'+authority},indent=2)+'\n'
        Path(target).write_text(value);os.chmod(target,0o600)
        write(target+'.meta',{'project':'passeway/naiveproxy','schema':1,'name':name})
    elif action=='site-needed':
        adapted,root=args
        config=json.loads(Path(adapted).read_text());page=Path(root,'index.html')
        serves_site=any(x.get('handler')=='file_server' and x.get('root')==root for x in walk(config))
        # Only replace the exact placeholder shipped by the previous manager.
        placeholder='d2b54e71ba979152b43c114f1fb783d441c8a40116aa6d2212179bdd9912b796'
        if not serves_site: print('no')
        elif page.is_symlink(): raise ValueError('站点首页不能是符号链接')
        elif not page.exists(): print('yes')
        elif page.is_file():
            old=page.stat().st_size<4096 and hashlib.sha256(page.read_bytes()).hexdigest()==placeholder
            print('yes' if old else 'no')
        else: raise ValueError('站点首页不是普通文件')
    elif action=='site-check':
        from html.parser import HTMLParser
        page=Path(args[0])
        if not 0<page.stat().st_size<=512*1024: raise ValueError('页面大小无效')
        text=page.read_text(encoding='utf-8')
        class Page(HTMLParser):
            def __init__(self): super().__init__();self.tags=set()
            def handle_starttag(self,tag,attrs): self.tags.add(tag)
        parser=Page();parser.feed(text);parser.close()
        if not {'html','head','title','body','main'}<=parser.tags or not text.rstrip().lower().endswith('</html>'):
            raise ValueError('下载内容不是完整站点首页')
    else: raise ValueError('未知操作')
except Exception as error:
    # Never echo configuration values or credentials in parser exceptions.
    print('配置或下载数据处理失败（'+type(error).__name__+'）；请检查输入、配置结构和发布文件。',file=sys.stderr)
    sys.exit(1)
PY
}
fetch_public_ip() {
    local family="$1" endpoint value
    for endpoint in https://api64.ipify.org https://icanhazip.com; do
        value=$(curl "-$family" -fsS --connect-timeout 3 --max-time 5 "$endpoint" 2>/dev/null) || continue
        data_tool ip "$value" 2>/dev/null && return 0
    done
    return 1
}
check_domain_dns() {
    local addresses detected='' address answer family
    addresses=$(timeout 10 bash -c "$(declare -f data_tool); data_tool dns \"\$1\"" _ "$1") || { fail '域名解析失败'; return 1; }
    for family in 4 6; do
        address=$(fetch_public_ip "$family") || continue
        detected+="$address"$'\n'
        if grep -Fxq "$address" <<< "$addresses"; then return 0; fi
    done
    printf '域名解析结果：\n%s\n检测到的公网地址：\n%s\n' "$addresses" "${detected:-查询失败}" >&2
    read -r -p '无法自动确认域名指向本机；已确认 DNS/NAT 配置正确？[y/N]: ' answer || return 1
    [[ "$answer" = y || "$answer" = Y ]] || { fail '请先修正域名解析'; return 1; }
}
country_name() {
    local value
    value=$(curl -4fsS --connect-timeout 3 --max-time 5 https://ipinfo.io/country 2>/dev/null) || value=''
    value=${value//$'\r'/}; value=${value//$'\n'/}
    if [[ "$value" =~ ^[A-Z]{2}$ ]]; then echo "$value"; else echo Naive; fi
}
check_ports() {
    local listeners
    listeners=$(ss -H -ltn) || return 1
    if awk '$4 ~ /:(80|443)$/ {found=1} END {exit !found}' <<< "$listeners"; then
        fail 'TCP 80 或 443 已被占用，请先自行处理；未结束任何进程'; return 1
    fi
    listeners=$(ss -H -lun) || return 1
    if awk '$4 ~ /:443$/ {found=1} END {exit !found}' <<< "$listeners"; then
        fail 'UDP 443 已被占用，请先自行处理'; return 1
    fi
}
download_core() {
    local stage="$1" arch release tag url digest version modules
    arch=$(get_architecture) || return 1
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 40 "$RELEASE_API" -o "$stage/release.json" || return 1
    release=$(data_tool release "$stage/release.json" "$arch") || return 1
    IFS=$'\t' read -r tag url digest <<< "$release"
    printf '下载 Caddy %s（%s）\n' "$tag" "$arch"
    curl -fL --retry 2 --connect-timeout 10 --max-time 180 "$url" -o "$stage/caddy.tar.gz" || return 1
    data_tool extract "$stage/caddy.tar.gz" "$digest" "$stage/caddy" || return 1
    version=$("$stage/caddy" version) && [[ "${version%% *}" = "$tag" ]] || { fail '内核无法运行或版本不符'; return 1; }
    modules=$("$stage/caddy" list-modules) && grep -Fxq http.handlers.forward_proxy <<< "$modules" || { fail '内核缺少 forward_proxy 模块'; return 1; }
}
validate_config() { "$1" validate --config "$2" --adapter caddyfile >/dev/null; }
stage_site() {
    local stage="$1" needed
    needed=$(data_tool site-needed "$stage/adapted.json" "$DATA_DIR/naive-site") || return 1
    [ "$needed" = yes ] || return 0
    curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 10 --max-time 40 \
        --max-filesize 524288 "$SITE_URL" -o "$stage/index.html" || { fail '站点首页下载失败'; return 1; }
    data_tool site-check "$stage/index.html" || return 1
}
prepare_account() {
    if ! getent group caddy >/dev/null; then
        if [ "$(get_system_type)" = alpine ]; then addgroup -S caddy || return 1
        else groupadd --system caddy || return 1; fi
    fi
    if ! id caddy >/dev/null 2>&1; then
        if [ "$(get_system_type)" = alpine ]; then adduser -S -D -H -h "$DATA_DIR" -s /sbin/nologin -G caddy caddy || return 1
        else useradd --system --gid caddy --home-dir "$DATA_DIR" --shell /usr/sbin/nologin caddy || return 1; fi
    fi
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$DATA_DIR/naive-site" || return 1
    chown root:caddy "$CONFIG_DIR" && chmod 750 "$CONFIG_DIR" &&
        chown caddy:caddy "$DATA_DIR" && chmod 750 "$DATA_DIR" &&
        chown root:caddy "$DATA_DIR/naive-site" && chmod 750 "$DATA_DIR/naive-site"
}
binary_capability() {
    [ "$(get_system_type)" != alpine ] || setcap cap_net_bind_service=+ep "$1"
}
service_template() {
    if [ "$(get_system_type)" = alpine ]; then
        cat <<EOF
#!/sbin/openrc-run
# Managed by passeway/naiveproxy
name="NaiveProxy (Caddy)"
command="$BINARY"
command_args="run --config $CONFIG_FILE --adapter caddyfile"
command_user="caddy:caddy"
supervisor="supervise-daemon"
respawn_delay=3
respawn_max=5
respawn_period=60
output_log="$LOG_FILE"
error_log="$LOG_FILE"
rc_ulimit="-n 1048576"
export HOME="$DATA_DIR"
export XDG_DATA_HOME="$DATA_DIR/.local/share"
export XDG_CONFIG_HOME="$DATA_DIR/.config"
depend() { need net; }
start_pre() { checkpath --file --mode 0640 --owner caddy:caddy "$LOG_FILE"; }
EOF
    else
        cat <<EOF
[Unit]
Description=NaiveProxy (Caddy)
After=network-online.target
Wants=network-online.target
[Service]
User=caddy
Group=caddy
Environment=HOME=$DATA_DIR
Environment=XDG_DATA_HOME=$DATA_DIR/.local/share
Environment=XDG_CONFIG_HOME=$DATA_DIR/.config
ExecStart=$BINARY run --config $CONFIG_FILE --adapter caddyfile
ExecReload=$BINARY reload --config $CONFIG_FILE --adapter caddyfile
Restart=on-failure
RestartSec=3
TimeoutStopSec=30s
LimitNOFILE=1048576
UMask=0027
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
    fi
}
configure_rotation() {
    [ "$(get_system_type)" = alpine ] || return 0
    mkdir -p "$(dirname "$CRON_FILE")" "$(dirname "$ROTATE_STATE")" || return 1
    write_file "$CONFIG_DIR/naive-logrotate.conf" 640 root:caddy <<EOF || return 1
$LOG_FILE {
    size 1M
    rotate 3
    compress
    missingok
    notifempty
    copytruncate
    su root caddy
}
EOF
    write_file "$CRON_FILE" 755 root:root <<EOF || return 1
#!/bin/sh
exec /usr/sbin/logrotate -s "$ROTATE_STATE" "$CONFIG_DIR/naive-logrotate.conf"
EOF
    rc-update add crond default 9>&- || return 1
    rc-service crond status >/dev/null 2>&1 9>&- || rc-service crond start 9>&- || return 1
}
wait_running() {
    local attempt
    for attempt in 1 2 3; do sleep 1; is_running || { fail '服务未保持运行，请查看日志'; return 1; }; done
}
# Snapshots retain the old binary inode (including Alpine file capabilities).
snapshot_files() {
    local i path
    TX_PATHS=("$BINARY" "$CONFIG_FILE" "$CLIENT_FILE" "$META_FILE" "$(service_file)" "$CONFIG_DIR/naive-logrotate.conf" "$CRON_FILE" "$DATA_DIR/naive-site/index.html")
    TX_PRESENT=()
    for i in "${!TX_PATHS[@]}"; do
        path=${TX_PATHS[$i]}
        [ ! -L "$path" ] || { fail "拒绝覆盖符号链接：$path"; return 1; }
        if [ -e "$path" ]; then
            [ -f "$path" ] || return 1
            if [ "$path" = "$BINARY" ]; then ln "$path" "$TX_STAGE/backup.$i" || return 1
            else cp -p "$path" "$TX_STAGE/backup.$i" || return 1; fi
            TX_PRESENT[$i]=yes
        else TX_PRESENT[$i]=no; fi
    done
}
restore_files() {
    local i path temporary result=0
    for i in "${!TX_PATHS[@]}"; do
        path=${TX_PATHS[$i]}
        if [ "${TX_PRESENT[$i]}" = yes ]; then
            if [ "$path" = "$BINARY" ]; then mv -f "$TX_STAGE/backup.$i" "$path" || result=1
            else
                temporary=$(mktemp "${path}.restore.XXXXXX") || { result=1; continue; }
                cp -p "$TX_STAGE/backup.$i" "$temporary" && mv -f "$temporary" "$path" || { rm -f "$temporary"; result=1; }
            fi
        else rm -f "$path" || result=1; fi
    done
    return "$result"
}
rollback_transaction() {
    local result=0
    service_action stop >/dev/null 2>&1 || { is_running && result=1; }
    if [ "$TX_ENABLED" = no ] && is_enabled; then disable_service >/dev/null 2>&1 || result=1; fi
    restore_files || result=1
    reload_manager || result=1
    if [ "$TX_ENABLED" = yes ]; then enable_service || result=1; fi
    if [ "$TX_RUNNING" = yes ]; then service_action start && wait_running || result=1; fi
    return "$result"
}
transaction_cleanup() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [ "$TX_ACTIVE" = yes ]; then
        if rollback_transaction; then echo '操作失败，已恢复原有程序、配置和服务状态。' >&2
        else fail "恢复未完全成功；备份保留在 $TX_STAGE，请检查服务日志"; return 1; fi
    fi
    rm -rf "$TX_STAGE"
    return "$status"
}
export_stage() {
    local binary="$1" config="$2" stage="$3" name=Naive
    if [ ! -f "$META_FILE" ] && [ ! -f "$CLIENT_FILE" ]; then name=$(country_name); fi
    "$binary" adapt --config "$config" --adapter caddyfile > "$stage/adapted.json" || return 1
    data_tool export "$stage/adapted.json" "$META_FILE" "$CLIENT_FILE" "$name" "$stage/clients"
}
refresh_clients() (
    require_managed || return 1
    umask 077
    local stage
    stage=$(mktemp -d "$CONFIG_DIR/.export.XXXXXX") || return 1
    trap 'rm -rf "$stage"' EXIT
    export_stage "$BINARY" "$CONFIG_FILE" "$stage" || return 1
    write_file "$CLIENT_FILE" 600 root:root < "$stage/clients" &&
        write_file "$META_FILE" 600 root:root < "$stage/clients.meta" || return 1
    cat "$CLIENT_FILE"
)
install_or_update() (
    umask 077
    operation="${1:-install}"
    get_architecture >/dev/null || return 1
    if [ "$operation" = update ]; then require_managed || return 1
    elif [ -e "$BINARY" ] || [ -e "$CONFIG_FILE" ] || [ -e "$(service_file)" ] ||
        [ -e /usr/lib/systemd/system/caddy.service ] || [ -e /lib/systemd/system/caddy.service ] || command -v caddy >/dev/null 2>&1; then
        fail '检测到已有 Caddy；本项目安装请用菜单 5 更新，其他部署请先自行处理'; return 1
    fi
    install_dependencies || return 1
    if [ "$operation" = install ]; then
        check_ports || return 1
        read -r -p '请输入已解析的域名: ' domain_input || return 1
        domain_input=$(data_tool domain "$domain_input") || return 1
        check_domain_dns "$domain_input" || return 1
        read -r -p '证书联系邮箱（可留空）: ' email_input || return 1
    fi
    mkdir -p "$(dirname "$BINARY")" || return 1
    TX_STAGE=$(mktemp -d "$(dirname "$BINARY")/.naive-install.XXXXXX") || return 1
    TX_ACTIVE=no; TX_RUNNING=no; TX_ENABLED=no
    trap transaction_cleanup EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM HUP
    download_core "$TX_STAGE" || return 1
    if [ "$operation" = install ]; then
        data_tool new "$TX_STAGE" "$domain_input" "$email_input" "$DATA_DIR/naive-site" || return 1
    else cp "$CONFIG_FILE" "$TX_STAGE/Caddyfile" || return 1; fi
    "$TX_STAGE/caddy" fmt --overwrite "$TX_STAGE/Caddyfile" >/dev/null || return 1
    validate_config "$TX_STAGE/caddy" "$TX_STAGE/Caddyfile" || return 1
    # Export is preflighted before touching any running service or original file.
    export_stage "$TX_STAGE/caddy" "$TX_STAGE/Caddyfile" "$TX_STAGE" || return 1
    stage_site "$TX_STAGE" || return 1
    prepare_account || return 1
    is_running && TX_RUNNING=yes
    is_enabled && TX_ENABLED=yes
    chown root:root "$TX_STAGE/caddy" && chmod 755 "$TX_STAGE/caddy" && binary_capability "$TX_STAGE/caddy" || return 1
    snapshot_files || return 1
    TX_ACTIVE=yes
    mv -f "$TX_STAGE/caddy" "$BINARY" || return 1
    write_file "$CONFIG_FILE" 640 root:caddy < "$TX_STAGE/Caddyfile" &&
        write_file "$CLIENT_FILE" 600 root:root < "$TX_STAGE/clients" &&
        write_file "$META_FILE" 600 root:root < "$TX_STAGE/clients.meta" || return 1
    if [ -f "$TX_STAGE/index.html" ]; then
        write_file "$DATA_DIR/naive-site/index.html" 644 root:caddy < "$TX_STAGE/index.html" || return 1
    fi
    unit_mode=644; [ "$(get_system_type)" != alpine ] || unit_mode=755
    service_template > "$TX_STAGE/service" || return 1
    write_file "$(service_file)" "$unit_mode" root:root < "$TX_STAGE/service" || return 1
    configure_rotation && reload_manager || return 1
    if [ "$operation" = install ] || [ "$TX_ENABLED" = yes ]; then enable_service || return 1; fi
    if [ "$operation" = install ] || [ "$TX_RUNNING" = yes ]; then
        service_action restart && wait_running || return 1
    fi
    TX_ACTIVE=no
    echo 'NaïveProxy 安装/更新完成。证书签发进度请查看日志。'
    cat "$CLIENT_FILE"
)
core_only() (
    # Do not replace a daemon's executable outside the transactional updater.
    if [ -e "$CONFIG_FILE" ] || [ -e "$(service_file)" ] || [ -e /usr/lib/systemd/system/caddy.service ] || [ -e /lib/systemd/system/caddy.service ] || is_running; then
        fail '已有 Caddy 服务，请使用管理菜单更新'; return 1
    fi
    [ ! -L "$BINARY" ] || { fail '拒绝覆盖符号链接'; return 1; }
    install_dependencies || return 1
    umask 077
    mkdir -p "$(dirname "$BINARY")" || return 1
    local stage
    stage=$(mktemp -d "$(dirname "$BINARY")/.naive-core.XXXXXX") || return 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM HUP
    download_core "$stage" && chown root:root "$stage/caddy" && binary_capability "$stage/caddy" && mv -f "$stage/caddy" "$BINARY"
)
start_or_restart() {
    require_managed || return 1
    validate_config "$BINARY" "$CONFIG_FILE" && service_action "$1" && wait_running
}
stop_service() { require_managed && service_action stop; }
uninstall_service() {
    require_managed || return 1
    local answer
    read -r -p '卸载程序与本项目配置？保留证书、站点与日志。[y/N]: ' answer || return 0
    [[ "$answer" = y || "$answer" = Y ]] || { echo '已取消'; return 0; }
    if is_running; then service_action stop || return 1; fi
    disable_service || return 1
    rm -f "$BINARY" "$CONFIG_FILE" "$CLIENT_FILE" "$META_FILE" "$(service_file)" "$CONFIG_DIR/naive-logrotate.conf" "$CRON_FILE" "$ROTATE_STATE" || return 1
    reload_manager || return 1
    rmdir "$CONFIG_DIR" 2>/dev/null || :
    echo 'NaïveProxy 已卸载；证书、站点、用户和日志已保留。'
}
show_logs() {
    local result
    trap ':' INT
    (
        trap - INT
        if [ "$(get_system_type)" = alpine ]; then exec tail -n 50 -F "$LOG_FILE" 9>&-
        else exec journalctl -u caddy -n 50 -f -o cat 9>&-; fi
    )
    result=$?
    trap 'exit 130' INT
    [ "$result" -eq 130 ] && return 0
    return "$result"
}
show_menu() {
    local installed='未安装' running='未运行' version='—' output
    is_installed && installed='已安装'
    is_running && running='已运行'
    if [ -x "$BINARY" ]; then
        output=$("$BINARY" version 2>/dev/null) && version=${output%% *} || version='未知'
    fi
    if [ -t 1 ] && [ -n "${TERM:-}" ]; then clear; fi
    printf '=== NaïveProxy 管理工具 ===\n安装状态: %s\n运行状态: %s\n运行版本: %s\n\n' "$installed" "$running" "$version"
    printf '%s\n' '1. 安装 NaïveProxy 服务'
    if is_installed; then
        printf '%s\n' '2. 启动 NaïveProxy 服务' '3. 停止 NaïveProxy 服务'
    fi
    printf '%s\n' '4. 卸载 NaïveProxy 服务'
    if is_installed; then
        printf '%s\n' '5. 更新 NaïveProxy 内核' '6. 查看 NaïveProxy 配置' '7. 重启 NaïveProxy 服务' '8. 查看 NaïveProxy 状态' '9. 查看 NaïveProxy 日志'
    fi
    printf '%s\n' '0. 退出' '==========================='
    read -r -p '请输入选项编号: ' choice
}
main() {
    [ "$(id -u)" = 0 ] || { fail '请以 root 运行'; return 1; }
    get_system_type >/dev/null || { fail '仅支持 Debian、Ubuntu、Alpine'; return 1; }
    get_architecture >/dev/null && ensure_lock_tool || return 1
    trap 'exit 130' INT; trap 'exit 143' TERM HUP
    case "${1:-}" in
        --core-only) with_lock core_only; return $?;;
        --install) with_lock install_or_update install; return $?;;
        --update) with_lock install_or_update update; return $?;;
        '') ;;
        *) fail '用法：naive.sh [--install|--update|--core-only]'; return 1;;
    esac
    while show_menu; do
        case "$choice" in
            1) with_lock install_or_update install;;
            2) with_lock start_or_restart start;;
            3) with_lock stop_service;;
            4) with_lock uninstall_service;;
            5) with_lock install_or_update update;;
            6) with_lock refresh_clients;;
            7) with_lock start_or_restart restart;;
            8) service_action status;;
            9) show_logs;;
            0) return 0;;
            *) fail '无效选项';;
        esac
        [ "$?" -eq 0 ] || echo '操作未完成，请检查上方错误信息。' >&2
        read -r -p '按 Enter 键继续...' || return 0
    done
    return 0
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi

