#!/bin/bash

# 颜色设置
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[0;37m'
NC='\033[0m' # No Color

# 打印彩色文本的函数
color_echo() {
    color=$1
    shift
    echo -e "${color}$@${NC}"
}

# 检测是否可以访问Google
check_google() {
    if curl -s --connect-timeout 5 -m 5 google.com >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查是否已安装Go
check_go_installed() {
    if command -v go >/dev/null 2>&1; then
        current_version=$(go version | awk '{print $3}' | sed 's/go//')
        return 0
    else
        return 1
    fi
}

# 检测系统架构
check_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            GOARCH="amd64"
            ;;
        aarch64|arm64)
            GOARCH="arm64"
            ;;
        *)
            color_echo $red "不支持的架构: $ARCH"
            exit 1
            ;;
    esac
    color_echo $green "检测到系统架构: $ARCH, 将使用Go $GOARCH 版本"
}

# 获取最新版本的Go
get_latest_version() {
    echo "正在获取最新版golang..."
    count=0
    
    # 检查是否可以访问Google
    if check_google; then
        can_google=0
    else
        can_google=1
    fi
    
    while :
    do
        install_version=""
        if [[ $can_google == 0 ]]; then
            install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://go.dev/dl/|grep -w downloadBox|grep src|grep -oE '[0-9]+\.[0-9]+\.?[0-9]*'|head -n 1)
        else
            install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://github.com/golang/go/tags|grep releases/tag|grep -v rc|grep -v beta|grep -oE '[0-9]+\.[0-9]+\.?[0-9]*'|head -n 1)
        fi
        
        # 处理版本号末尾可能有的点号
        [[ ${install_version: -1} == '.' ]] && install_version=${install_version%?}
        
        if [[ -z $install_version ]]; then
            if [[ $count -lt 3 ]]; then
                color_echo $yellow "获取go版本号超时, 正在重试..."
            else
                color_echo $red "\n获取go版本号失败!"
                return 1
            fi
        else
            break
        fi
        count=$((count+1))
    done
    
    color_echo $green "最新版golang: $(color_echo $blue $install_version)"
    
    # 检查当前版本
    if check_go_installed; then
        if [[ "$current_version" == "$install_version" ]]; then
            color_echo $green "当前Go版本 $current_version 已是最新版本，无需更新"
            return 2
        else
            color_echo $yellow "当前Go版本: $current_version, 将更新到: $install_version"
        fi
    fi
    
    return 0
}

# 下载并安装Go
download_and_install() {
    local version=$1
    local arch=$2
    
    # 构建下载URL
    DOWNLOAD_URL="https://dl.google.com/go/go${version}.linux-${arch}.tar.gz"
    FILENAME="go${version}.linux-${arch}.tar.gz"
    
    color_echo $green "下载链接: $DOWNLOAD_URL"
    
    # 下载Go安装包
    color_echo $green "开始下载..."
    wget -q --show-progress "$DOWNLOAD_URL" -O "$FILENAME"
    
    if [ $? -ne 0 ]; then
        color_echo $yellow "从Google下载失败，尝试从golang.org下载..."
        BACKUP_URL="https://golang.org/dl/go${version}.linux-${arch}.tar.gz"
        color_echo $green "备用下载链接: $BACKUP_URL"
        wget -q --show-progress "$BACKUP_URL" -O "$FILENAME"
        
        if [ $? -ne 0 ]; then
            color_echo $yellow "从golang.org下载失败，尝试从GitHub下载..."
            GITHUB_URL="https://github.com/golang/go/releases/download/go${version}/go${version}.linux-${arch}.tar.gz"
            color_echo $green "GitHub下载链接: $GITHUB_URL"
            wget -q --show-progress "$GITHUB_URL" -O "$FILENAME"
            
            if [ $? -ne 0 ]; then
                color_echo $red "所有下载尝试均失败，请检查网络连接或手动下载"
                return 1
            fi
        fi
    fi
    
    color_echo $green "下载完成: $FILENAME"
    
    # 删除旧版本(如果存在)
    color_echo $green "移除旧版本Go(如果存在)..."
    sudo rm -rf /usr/local/go
    
    # 解压到/usr/local
    color_echo $green "解压Go到/usr/local目录..."
    sudo tar -C /usr/local -xzf "$FILENAME"
    
    if [ $? -ne 0 ]; then
        color_echo $red "解压失败"
        return 1
    fi
    
    # 设置环境变量
    color_echo $green "设置环境变量..."
    
    # 为当前用户设置
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" ~/.profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
        color_echo $green "已添加Go到用户PATH环境变量"
    else
        color_echo $green "Go环境变量已存在于~/.profile"
    fi
    
    # 为系统所有用户设置
    if [ $(id -u) -eq 0 ]; then
        if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" /etc/profile; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
            color_echo $green "已添加Go到系统级PATH环境变量"
        fi
    fi
    
    # 设置GOPATH
    if ! grep -q "export GOPATH=\$HOME/go" ~/.profile; then
        echo 'export GOPATH=$HOME/go' >> ~/.profile
        echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
        color_echo $green "已设置GOPATH环境变量"
    fi
    
    # 应用环境变量到当前会话
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin
    
    # 创建Go工作目录
    if [ ! -d "$HOME/go" ]; then
        mkdir -p "$HOME/go/src" "$HOME/go/bin" "$HOME/go/pkg"
        color_echo $green "已创建Go工作目录: $HOME/go"
    fi
    
    # 清理下载文件
    color_echo $green "清理下载文件..."
    rm "$FILENAME"
    
    # 验证安装
    color_echo $green "验证Go安装..."
    GO_VERSION_CHECK=$(/usr/local/go/bin/go version 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        color_echo $green "Go安装成功!"
        color_echo $blue "$GO_VERSION_CHECK"
        return 0
    else
        color_echo $red "Go安装可能有问题，请检查"
        return 1
    fi
}

# 主函数
main() {
    # 检查系统架构
    check_arch
    
    # 获取最新版本
    get_latest_version
    result=$?
    
    if [ $result -eq 1 ]; then
        color_echo $red "获取版本信息失败，退出安装"
        exit 1
    elif [ $result -eq 2 ]; then
        color_echo $green "已安装最新版本，无需更新"
        exit 0
    fi
    
    # 下载并安装
    download_and_install "$install_version" "$GOARCH"
    
    if [ $? -eq 0 ]; then
        color_echo $green "Go $install_version 安装完成！"
        
        # 自动应用环境变量
        color_echo $green "正在应用环境变量更改..."
        
        # 将应用环境变量的命令保存到临时文件
        TEMP_SCRIPT=$(mktemp)
        cat > $TEMP_SCRIPT << 'EOF'
#!/bin/bash
source ~/.profile
export PS1="(Go env) $PS1"
echo -e "\033[0;32m环境变量已应用，Go环境已激活\033[0m"
echo -e "\033[0;34mGo版本: $(go version)\033[0m"
echo -e "\033[0;32mGOROOT: $GOROOT\033[0m"
echo -e "\033[0;32mGOPATH: $GOPATH\033[0m"
EOF
        
        chmod +x $TEMP_SCRIPT
        
        color_echo $yellow "请运行以下命令以立即应用环境变量:"
        color_echo $cyan "source ~/.profile"
        color_echo $green "或重新打开终端会话"
        
        # 为当前会话自动应用环境变量
        export PATH=$PATH:/usr/local/go/bin
        export GOPATH=$HOME/go
        export PATH=$PATH:$GOPATH/bin
        
        # 确认当前会话中的可用性
        if command -v go >/dev/null 2>&1; then
            color_echo $green "当前会话中Go已可用:"
            color_echo $blue "$(go version)"
        fi
        
        # 删除临时脚本
        rm $TEMP_SCRIPT
    else
        color_echo $red "Go安装失败，请检查错误信息"
        exit 1
    fi
}

# 执行主函数
main
