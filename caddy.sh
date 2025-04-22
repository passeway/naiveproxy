#!/bin/bash

set -e

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

# 拼接下载地址和文件名
FILENAME="caddy-${ARCH_TAG}-${LATEST_VERSION}.tar.gz"
URL="https://github.com/passeway/naiveproxy/releases/download/${LATEST_VERSION}/${FILENAME}"

echo "📥 正在下载 $FILENAME ..."
curl -L "$URL" -o "$FILENAME" || { echo "❌ 下载失败"; exit 1; }

# 解压到临时目录再移动，防止压缩包中不是单一文件
TMP_DIR=$(mktemp -d)
tar -xvzf "$FILENAME" -C "$TMP_DIR" || { echo "❌ 解压失败"; exit 1; }

# 查找解压出的 caddy 可执行文件并移动
CADDY_BIN=$(find "$TMP_DIR" -type f -name "caddy")
if [[ ! -f "$CADDY_BIN" ]]; then
    echo "❌ 解压后未找到 caddy 可执行文件"
    exit 1
fi

mv "$CADDY_BIN" /usr/bin/caddy
chmod +x /usr/bin/caddy

# 清理文件
rm -rf "$TMP_DIR" "$FILENAME"

echo "✅ 安装完成，当前版本："
/usr/bin/caddy version
