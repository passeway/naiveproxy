#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'


# 检查是否以 root 权限运行
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请以 root 权限运行此脚本（使用 sudo）${RESET}" | tee -a "$LOG_FILE"
    exit 1
  fi
}


# 检查 NaïveProxy 安装状态
check_naiveproxy_status() {
  if command -v caddy &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# 检查 NaïveProxy 运行状态
check_naiveproxy_running() {
  if systemctl status caddy | grep -q "Active: active (running)"; then
    return 0
  else
    return 1
  fi
}


# 检查 80 和 443 端口
check_ports() {
  echo "检测80|443是否被占用"
  sleep 1

  # 查找占用 80 或 443 的进程
  ports_info=$(ss -ltnp | awk '$4 ~ /:(80|443)$/')

  if [[ -z "$ports_info" ]]; then
    echo "检测80|443没有被占用"
    sleep 1
  else
    echo "$ports_info"
    read -rp "是否结束占用端口的进程？按 Y 确认，其他键退出 [Y/n]: " yn
    yn=${yn:-Y}  # 如果用户直接回车，默认赋值为 Y
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      pids=$(echo "$ports_info" | grep -oP 'pid=\K[0-9]+' | sort -u)
      if [[ -n "$pids" ]]; then
        echo "$pids" | xargs -r kill -9
        echo "已结束80|443占用进程"
        sleep 1
      else
        echo "未结束80|443占用进程"
        exit 1
      fi
    else
      echo "操作已取消"
      exit 1
    fi
  fi
}




# 生成一个未被占用的端口
generate_free_port() {
  local port
  while true; do
    port=$(shuf -i 1024-65535 -n 1)  # 生成随机端口
    if ! ss -tuln | grep -q ":$port"; then  # 检查端口是否被占用
      echo "$port"
      break
    fi
  done
}

# 安装 NaïveProxy
install_naiveproxy() {
  echo "正在安装 NaïveProxy"

  # 检查端口和root权限
  check_root
  check_ports
    
  # 读取用户输入的域名
  read -p "请输入您的已解析域名: " domain_name

  if [[ -z "${domain_name}" ]]; then
    echo "域名不能为空。请重新运行脚本并输入有效的域名。"
    return 1
  fi
  
  # 检查域名解析是否指向本机
  domain_ip=$(getent hosts "${domain_name}" | awk '{ print $1 }' | head -n 1)
  local_ip=$(curl -s http://ipinfo.io/ip)

  if [[ -z "${domain_ip}" || "${domain_ip}" != "${local_ip}" ]]; then
    echo "域名解析的 IP 地址 (${domain_ip}) 与本机外部 IP 地址 (${local_ip}) 不一致，请检查域名解析设置"
    exit 1
  fi
  echo "域名解析正确继续安装"

  # 生成安全范围内的随机端口
  random_http_port=$(generate_free_port)
  random_proxy_port=$(generate_free_port)

  # 生成随机邮箱用户名和密码
  admin_user=$(tr -dc A-Za-z < /dev/urandom | head -c 6)
  admin_pass=$(tr -dc A-Za-z < /dev/urandom | head -c 6)
  admin_mail=$(tr -dc A-Za-z < /dev/urandom | head -c 6)

  # 更新和升级系统包
  echo "正在升级和更新系统包"
  if ! apt-get update && apt-get upgrade -y; then
    echo "系统包更新失败。请检查网络连接或包管理器。"
    return 1
  fi

  # 下载 Caddy 内核
  bash <(curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/caddy.sh)


  # 创建并配置 Caddyfile
  echo "正在创建并配置 Caddyfile"
  if ! mkdir -p /etc/caddy && touch /etc/caddy/Caddyfile; then
    echo "无法创建 Caddyfile"
    return 1
  fi

  cat <<EOF > /etc/caddy/Caddyfile
{
  http_port ${random_http_port}
}
:${random_proxy_port}, ${domain_name}:${random_proxy_port}
tls ${admin_mail}@gmail.com
route {
  forward_proxy {
    basic_auth ${admin_user} ${admin_pass}
    hide_ip
    hide_via
    probe_resistance
  }
 reverse_proxy https://demo.cloudreve.org {
    header_up Host {upstream_hostport}
  }
}
EOF

  # 格式化并验证 Caddyfile
  if ! caddy fmt --overwrite /etc/caddy/Caddyfile || ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "Caddyfile 格式或验证失败"
    return 1
  fi

  # 确保存在 Caddy 用户组和用户
  if ! getent group caddy > /dev/null; then
    groupadd --system caddy
  fi

  if ! id "caddy" > /dev/null 2>&1; then
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
  fi

  # 创建 systemd 服务并配置 Caddy 服务
  if ! touch /etc/systemd/system/caddy.service; then
    echo "无法创建 caddy.service"
    return 1
  fi

  cat <<EOF > /etc/systemd/system/caddy.service
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
EOF

  # 重载 systemd 守护进程并启动 Caddy 服务
  systemctl daemon-reload
  systemctl enable caddy
  if ! systemctl start caddy; then
    echo "Caddy 服务启动失败"
    return 1
  fi

  # 确认 Caddy 服务状态
  if check_naiveproxy_running; then
    echo "NaïveProxy 安装成功并正在运行"
  else
    echo "Caddy 未正确启动"
    return 1
  fi

  # 输出 NaïveProxy 配置
  # 获取本机IP地址
  HOST_IP=$(curl -s http://checkip.amazonaws.com)

  # 获取IP所在国家
  IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

  # 生成客户端配置信息
  cat << EOF > /etc/caddy/config.txt

naive+https://${admin_user}:${admin_pass}@${domain_name}:${random_proxy_port}#${IP_COUNTRY}

{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${admin_user}:${admin_pass}@${domain_name}:${random_proxy_port}"
}

EOF

  # 输出 NaïveProxy 配置
  echo "naive+https://${admin_user}:${admin_pass}@${domain_name}:${random_proxy_port}#${IP_COUNTRY}"

  cat <<EOF
{
  "listen": "socks://127.0.0.1:1080",
  "proxy": "https://${admin_user}:${admin_pass}@${domain_name}:${random_proxy_port}"
}
EOF
}



# 启动 NaïveProxy
start_naiveproxy() {
  echo "正在启动 NaïveProxy"
  if systemctl start caddy; then
    echo "NaïveProxy 启动成功"
  else
    echo "NaïveProxy 启动失败"
  fi
}

# 停止 NaïveProxy
stop_naiveproxy() {
  echo "正在停止 NaïveProxy"
  if systemctl stop caddy; then
    echo "NaïveProxy 停止成功"
  else
    echo "NaïveProxy 停止失败"
  fi
}



# 更新 NaïveProxy
update_naiveproxy() {
  echo "正在更新 NaïveProxy"

  #停止 Caddy 服务器
  systemctl stop caddy


  # 下载 Caddy 服务器
  bash <(curl -fsSL https://raw.githubusercontent.com/passeway/naiveproxy/main/caddy.sh)

  # 启动 Caddy 服务器
  systemctl start caddy

  echo "NaïveProxy 更新成功"
}


# 查看 NaïveProxy 配置
view_naiveproxy() {
  cat /etc/caddy/config.txt
}


# 卸载 NaïveProxy
uninstall_naiveproxy() {
  echo "正在卸载 NaïveProxy"

  # 停止 Caddy 服务
  systemctl stop caddy

  # 禁用 Caddy 服务
  systemctl disable caddy

  # 删除 Caddy 可执行文件
  rm /usr/bin/caddy

  # 删除 Caddy 的配置文件
  rm -rf /etc/caddy
  rm -rf /var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/*

  # 删除 systemd 服务配置
  rm /etc/systemd/system/caddy.service
  systemctl daemon-reload


  echo "NaïveProxy 卸载成功"
}

# 显示菜单
show_menu() {
  clear
  check_naiveproxy_status
  naiveproxy_status=$?
  check_naiveproxy_running
  naiveproxy_running=$?

  echo -e "${GREEN}=== NaïveProxy 管理工具 ===${RESET}"
  echo -e "${GREEN}当前状态: $(if [ ${naiveproxy_status} -eq 0 ]; then echo "${GREEN}已安装${RESET}"; else echo "${RED}未安装${RESET}"; fi)${RESET}"
  echo -e "${GREEN}运行状态: $(if [ ${naiveproxy_running} -eq 0 ]; then echo "${GREEN}已运行${RESET}"; else echo "${RED}未运行${RESET}"; fi)${RESET}"
  echo ""
  echo "1. 安装 NaïveProxy 服务"
  echo "2. 启动 NaïveProxy 服务"
  echo "3. 停止 NaïveProxy 服务"
  echo "4. 卸载 NaïveProxy 服务"
  echo "5. 更新 NaïveProxy 内核"
  echo "6. 查看 NaïveProxy 配置"
  echo "0. 退出"
  echo -e "${GREEN}===========================${RESET}"
  read -p "请输入选项编号: " choice
  echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
while true; do
  show_menu
  case "${choice}" in
    1)
      install_naiveproxy
      ;;
    2)
      start_naiveproxy
      ;;
    3)
      stop_naiveproxy
      ;;
    4)
      uninstall_naiveproxy
      ;;
    5)
      update_naiveproxy
      ;;      
    6)
      view_naiveproxy
      ;;
    0)
      echo -e "${GREEN}已退出 NaïveProxy${RESET}"
      exit 0
      ;;
    *)
      echo -e "${RED}无效的选项${RESET}"
      ;;
  esac
  read -p "按 enter 键继续..."
done
