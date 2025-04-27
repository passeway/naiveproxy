#!/bin/bash

# 取消 CentOS 别名
[[ -f /etc/redhat-release ]] && unalias -a

can_google=1
force_mode=0
sudo=""
os="Linux"
install_version=""
proxy_url="https://goproxy.cn"

####### 颜色代码 ########
red="31m"
green="32m"
yellow="33m"
blue="36m"
fuchsia="35m"

color_echo(){
    echo -e "\033[$1${@:2}\033[0m"
}

####### 解析参数 #########
while [[ $# > 0 ]]; do
    case "$1" in
        -v|--version)
        install_version="$2"
        echo -e "准备安装 $(color_echo ${blue} $install_version) 版本 Golang..\n"
        shift
        ;;
        -f)
        force_mode=1
        echo -e "强制更新 Golang..\n"
        ;;
        *)
        ;;
    esac
    shift
done
#############################

ip_is_connect(){
    ping -c2 -i0.3 -W1 $1 &>/dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

setup_env(){
    if [[ $sudo == "" ]]; then
        profile_path="/etc/profile"
    elif [[ -e ~/.zshrc ]]; then
        profile_path="$HOME/.zprofile"
    fi

    # 取消 GOPATH 相关配置
    sed -i '/export GOPATH/d' $profile_path
    sed -i '/export PATH=.*\$GOPATH\/bin/d' $profile_path

    # 确保 Go 的路径在环境变量中
    if [[ -z `echo $PATH | grep /usr/local/go/bin` ]]; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> $profile_path
    fi

    # 设置 GO111MODULE 环境变量
    echo "export GO111MODULE=on" >> ~/.bashrc
    source ~/.bashrc

    # 重新加载环境变量
    source $profile_path
}

check_network(){
    ip_is_connect "golang.org"
    [[ ! $? -eq 0 ]] && can_google=0
}

setup_proxy(){
    if [[ $can_google == 0 && `go env | grep proxy.golang.org` ]]; then
        go env -w GO111MODULE=on
        go env -w GOPROXY=$proxy_url,direct
        color_echo $green "当前网络环境为国内环境, 成功设置 goproxy 代理!"
    fi
}

sys_arch(){
    arch=$(uname -m)
    if [[ `uname -s` == "Darwin" ]]; then
        os="Darwin"
        if [[ "$arch" == "arm64" ]]; then
            vdis="darwin-arm64"
        else
            vdis="darwin-amd64"
        fi
    else
        if [[ "$arch" == "i686" ]] || [[ "$arch" == "i386" ]]; then
            vdis="linux-386"
        elif [[ "$arch" == *"armv7"* ]] || [[ "$arch" == "armv6l" ]]; then
            vdis="linux-armv6l"
        elif [[ "$arch" == *"armv8"* ]] || [[ "$arch" == "aarch64" ]]; then
            vdis="linux-arm64"
        elif [[ "$arch" == *"s390x"* ]]; then
            vdis="linux-s390x"
        elif [[ "$arch" == "ppc64le" ]]; then
            vdis="linux-ppc64le"
        elif [[ "$arch" == "x86_64" ]]; then
            vdis="linux-amd64"
        fi
    fi
    [ $(id -u) != "0" ] && sudo="sudo"
}

install_go(){
    if [[ -z $install_version ]]; then
        count=0
        while :
        do
            install_version=""
            if [[ $can_google == 0 ]]; then
                install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://go.dev/dl/ | grep -w downloadBox | grep src | grep -oE '[0-9]+\.[0-9]+\.?[0-9]*' | head -n 1)
            else
                install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://github.com/golang/go/tags | grep releases/tag | grep -v rc | grep -v beta | grep -oE '[0-9]+\.[0-9]+\.?[0-9]*' | head -n 1)
            fi
            [[ ${install_version: -1} == '.' ]] && install_version=${install_version%?}
            if [[ -z $install_version ]]; then
                if [[ $count < 3 ]]; then
                    color_echo $yellow "获取 Go 版本号超时"
                else
                    color_echo $red "\n获取 Go 版本号失败"
                    exit 1
                fi
            else
                break
            fi
            count=$(($count+1))
        done
        echo "Go version $(color_echo $blue "go$install_version")"
    fi

    if [[ $force_mode == 0 && `command -v go` ]]; then
        if [[ `go version | awk '{print $3}' | grep -Eo "[0-9.]+"` == $install_version ]]; then
            return
        fi
    fi

    file_name="go${install_version}.$vdis.tar.gz"
    local temp_path=$(mktemp -d)

    curl -H 'Cache-Control: no-cache' -L https://dl.google.com/go/$file_name -o $file_name
    tar -C $temp_path -xzf $file_name
    if [[ $? != 0 ]]; then
        color_echo $yellow "\n解压失败! 正在重新下载..."
        rm -rf $file_name
        curl -H 'Cache-Control: no-cache' -L https://dl.google.com/go/$file_name -o $file_name
        tar -C $temp_path -xzf $file_name
        [[ $? != 0 ]] && { color_echo $yellow "\n解压失败!"; rm -rf $temp_path $file_name; exit 1; }
    fi

    [[ -e /usr/local/go ]] && $sudo rm -rf /usr/local/go
    $sudo mv $temp_path/go /usr/local/
    rm -rf $temp_path $file_name
}

main(){
    sys_arch
    check_network
    install_go
    setup_env
    setup_proxy
    go version
}

main
