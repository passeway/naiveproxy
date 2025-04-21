#!/bin/bash

# 设置固定路径
CADDY_PATH="/usr/bin/caddy"

# ========== 检查 caddy 是否存在 ==========
if [[ ! -f "$CADDY_PATH" ]]; then
    echo "❌ 错误：未找到文件 $CADDY_PATH"
    exit 1
fi

# ========== 自动识别架构 ==========
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64) ARCH="amd64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) ARCH="$ARCH_RAW" ;;
esac

# ========== 自动获取版本号 ==========
VERSION_OUTPUT=$("$CADDY_PATH" version 2>/dev/null)
if [[ $? -ne 0 || -z "$VERSION_OUTPUT" ]]; then
    echo "⚠️ 无法通过 '$CADDY_PATH version' 获取版本号，默认使用 'unknown'"
    VERSION="unknown"
else
    VERSION=$(echo "$VERSION_OUTPUT" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
fi

# ========== 构建包名 ==========
NAME="caddy-${ARCH}-${VERSION}"
DIR="/tmp/${NAME}"

# ========== 打包流程 ==========
mkdir -p "$DIR"
cp "$CADDY_PATH" "${DIR}/caddy"

tar -czvf "${NAME}.tar.gz" -C /tmp "${NAME}"
rm -rf "$DIR"

echo "✅ 打包完成：${NAME}.tar.gz"
