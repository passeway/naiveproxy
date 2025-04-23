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

# 获取最新版本 tag（包含 v 前缀）
LATEST_TAG=$(curl -fsSL https://api.github.com/repos/passeway/naiveproxy/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
if [[ -z "$LATEST_TAG" ]]; then
    echo "❌ 无法获取最新版本号"
    exit 1
fi

# 获取该版本下的下载链接列表
ASSETS_JSON=$(curl -fsSL "https://api.github.com/repos/passeway/naiveproxy/releases/tags/${LATEST_TAG}")
DOWNLOAD_URL=$(echo "$ASSETS_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep "$ARCH_TAG" | grep '\.tar\.gz$' | head -n 1)

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "❌ 未找到适用于架构 $ARCH_TAG 的 tar.gz 文件"
    exit 1
fi

# 提取文件名
FILENAME=$(basename "$DOWNLOAD_URL")

# 下载并解压
curl -L "$DOWNLOAD_URL" -o "$FILENAME" || { echo "❌ 下载失败"; exit 1; }
tar -xvzf "$FILENAME" -C /usr/bin/ || { echo "❌ 解压失败"; exit 1; }

# 设置权限
chmod +x /usr/bin/caddy
caddy version

# 清理
rm -f "$FILENAME"
