#!/bin/bash

# 自动识别架构
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH_TAG="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH_TAG="arm64"
else
    echo "❌ 不支持的架构：$ARCH"
    exit 1
fi

# 获取最新版本号
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/passeway/naiveproxy/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')

if [[ -z "$LATEST_VERSION" ]]; then
    echo "❌ 无法获取最新版本号"
    exit 1
fi

echo "最新版本：$LATEST_VERSION"

# 拼接下载地址
FILENAME="caddy-${ARCH_TAG}-${LATEST_VERSION}.tar.gz"
URL="https://github.com/passeway/naiveproxy/releases/download/${LATEST_VERSION}/${FILENAME}"
curl -L "$URL" -o "$FILENAME" || { echo "❌ 下载失败"; exit 1; }
tar -xvzf "$FILENAME" -C /usr/bin/ || { echo "❌ 解压失败"; exit 1; }

# 设置权限
chmod +x /usr/bin/caddy

# 清理文件
rm -f "$FILENAME"

echo "Caddy 安装完成 /usr/bin/caddy"
