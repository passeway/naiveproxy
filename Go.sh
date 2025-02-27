#!/bin/bash

# 设置颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        GOARCH="amd64"
        ;;
    aarch64|arm64)
        GOARCH="arm64"
        ;;
    *)
        echo -e "${YELLOW}不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}检测到系统架构: $ARCH, 将使用Go $GOARCH 版本${NC}"

# 从Go官网网页解析最新版本下载链接
echo "正在获取最新版Go的下载链接..."
DOWNLOAD_PAGE=$(curl -s https://go.dev/dl/)

# 提取适合当前架构的最新稳定版本下载链接
DOWNLOAD_LINK=$(echo "$DOWNLOAD_PAGE" | grep -o "https://.*linux-${GOARCH}.tar.gz" | head -1)

if [ -z "$DOWNLOAD_LINK" ]; then
    echo -e "${YELLOW}无法从官网获取下载链接，请检查网络连接${NC}"
    # 使用备选方案，硬编码最新版本
    echo -e "${YELLOW}使用备选方案...${NC}"
    GO_VERSION="go1.22.0"
    DOWNLOAD_LINK="https://dl.google.com/go/${GO_VERSION}.linux-${GOARCH}.tar.gz"
fi

echo -e "${GREEN}使用下载链接: $DOWNLOAD_LINK${NC}"
FILENAME=$(basename "$DOWNLOAD_LINK")
GO_VERSION=$(echo "$FILENAME" | sed 's/\(go[0-9.]*\).*/\1/')

# 下载Go安装包
echo "开始下载 $DOWNLOAD_LINK ..."
wget -q --show-progress "$DOWNLOAD_LINK" -O "$FILENAME"

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}下载失败，请检查网络连接${NC}"
    exit 1
fi

echo -e "${GREEN}下载完成: $FILENAME${NC}"

# 删除旧版本(如果存在)
echo "移除旧版本Go(如果存在)..."
sudo rm -rf /usr/local/go

# 解压到/usr/local
echo "解压Go到/usr/local目录..."
sudo tar -C /usr/local -xzf $FILENAME

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}解压失败${NC}"
    exit 1
fi

# 设置环境变量
echo "设置环境变量..."
# 为当前用户设置
if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    echo -e "${GREEN}已添加Go到用户PATH环境变量${NC}"
else
    echo -e "${GREEN}Go环境变量已存在于~/.profile${NC}"
fi

# 为root用户设置系统环境变量
if [ $(id -u) -eq 0 ]; then
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
        echo -e "${GREEN}已添加Go到系统级PATH环境变量${NC}"
    fi
fi

# 应用环境变量到当前会话
export PATH=$PATH:/usr/local/go/bin

# 清理下载文件
echo "清理下载文件..."
rm $FILENAME

# 验证安装
echo "验证Go安装..."
GO_VERSION_CHECK=$(/usr/local/go/bin/go version 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Go安装成功!${NC}"
    echo -e "${GREEN}$GO_VERSION_CHECK${NC}"
    echo -e "${YELLOW}请运行 'source ~/.profile' 或重新登录以应用环境变量更改${NC}"
    
    # 创建Go工作目录
    if [ ! -d "$HOME/go" ]; then
        mkdir -p "$HOME/go/src" "$HOME/go/bin" "$HOME/go/pkg"
        echo -e "${GREEN}已创建Go工作目录: $HOME/go${NC}"
        
        # 设置GOPATH环境变量
        if ! grep -q "export GOPATH=\$HOME/go" ~/.profile; then
            echo 'export GOPATH=$HOME/go' >> ~/.profile
            echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
            echo -e "${GREEN}已添加GOPATH环境变量${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Go安装可能有问题，请检查${NC}"
fi
