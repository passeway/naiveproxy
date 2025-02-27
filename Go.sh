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

# 从GitHub Go仓库的releases API获取最新版本号
echo "正在获取Go最新版本信息..."
LATEST_VERSION=$(curl -s https://go.dev/VERSION?m=text)

# 备选方案：如果上面的方法失败，尝试使用固定版本
if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}无法自动获取最新版本号，使用备选方法...${NC}"
    # 尝试从golang.org获取
    LATEST_VERSION=$(curl -s https://golang.org/VERSION?m=text)
fi

# 如果仍然失败，使用硬编码的最新版本
if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}无法在线获取版本信息，使用内置版本号...${NC}"
    LATEST_VERSION="go1.22.0"
    echo -e "${GREEN}使用版本: $LATEST_VERSION${NC}"
else
    echo -e "${GREEN}找到最新版本: $LATEST_VERSION${NC}"
fi

# 构建下载URL
DOWNLOAD_URL="https://dl.google.com/go/${LATEST_VERSION}.linux-${GOARCH}.tar.gz"
FILENAME="${LATEST_VERSION}.linux-${GOARCH}.tar.gz"

# 下载Go安装包
echo "开始下载 $DOWNLOAD_URL ..."
wget -q --show-progress $DOWNLOAD_URL -O $FILENAME

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}下载失败，尝试备用下载地址...${NC}"
    # 备用下载地址
    BACKUP_URL="https://golang.org/dl/${LATEST_VERSION}.linux-${GOARCH}.tar.gz"
    echo "尝试从 $BACKUP_URL 下载..."
    wget -q --show-progress $BACKUP_URL -O $FILENAME
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}所有下载尝试均失败，请检查网络连接或手动下载${NC}"
        exit 1
    fi
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
if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.profile; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    echo -e "${GREEN}已添加Go到PATH环境变量${NC}"
else
    echo -e "${GREEN}Go环境变量已存在于~/.profile${NC}"
fi

# 如果是root用户，也添加到系统级profile
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
GO_VERSION=$(go version)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Go安装成功!${NC}"
    echo -e "${GREEN}$GO_VERSION${NC}"
    echo -e "${YELLOW}请运行 'source ~/.profile' 或重新登录以应用环境变量更改${NC}"
else
    echo -e "${YELLOW}Go安装可能有问题，请检查${NC}"
fi
