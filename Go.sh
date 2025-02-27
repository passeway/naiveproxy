#!/bin/bash


# Cancel CentOS alias if present
[[ -f /etc/redhat-release ]] && unalias -a

can_google=1
force_mode=0
sudo=""
os="Linux"
install_version=""
proxy_url="https://goproxy.cn"

####### Color codes ########
red="31m"      
green="32m"  
yellow="33m" 
blue="36m"
fuchsia="35m"

color_echo(){
    echo -e "\033[$1${@:2}\033[0m"
}

####### Parse parameters ########
while [[ $# > 0 ]]; do
    case "$1" in
        -v|--version)
            install_version="$2"
            echo -e "准备安装$(color_echo ${blue} $install_version)版本golang..\n"
            shift
            ;;
        -f)
            force_mode=1
            echo -e "强制更新golang..\n"
            ;;
        *)
            # Unknown option
            ;;
    esac
    shift
done

ip_is_connect(){
    ping -c2 -i0.3 -W1 "$1" &>/dev/null
    [[ $? -eq 0 ]] && return 0 || return 1
}

setup_env(){
    # Set profile path based on sudo usage and shell
    if [[ $sudo == "" ]]; then
        profile_path="/etc/profile"
    elif [[ -e ~/.zshrc ]]; then
        profile_path="$HOME/.zprofile"
    fi

    # Set GOPATH to /home/go if not already defined (no user input)
    if [[ $sudo == "" && -z "$GOPATH" ]]; then
        GOPATH="/home/go"  # Fixed GOPATH, no confirmation required
        echo "设置GOPATH为: `color_echo $blue $GOPATH`"
        echo "export GOPATH=$GOPATH" >> "$profile_path"
        echo "export PATH=\$PATH:\$GOPATH/bin" >> "$profile_path"
        mkdir -p "$GOPATH"
    fi

    # Add /usr/local/go/bin to PATH if not present
    if [[ -z "$(echo $PATH | grep /usr/local/go/bin)" ]]; then
        echo "export PATH=\$PATH:/usr/local/go/bin" >> "$profile_path"
    fi
    source "$profile_path"
}

check_network(){
    ip_is_connect "golang.org"
    [[ $? -ne 0 ]] && can_google=0
}

setup_proxy(){
    if [[ $can_google == 0 && "$(go env | grep proxy.golang.org)" ]]; then
        go env -w GO111MODULE=on
        go env -w GOPROXY=$proxy_url,direct
        color_echo $green "当前网络环境为国内环境, 成功设置goproxy代理!"
    fi
}

sys_arch(){
    arch=$(uname -m)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        os="Darwin"
        [[ "$arch" == "arm64" ]] && vdis="darwin-arm64" || vdis="darwin-amd64"
    else
        case "$arch" in
            "i686"|"i386") vdis="linux-386" ;;
            *"armv7"*|"armv6l") vdis="linux-armv6l" ;;
            *"armv8"*|"aarch64") vdis="linux-arm64" ;;
            *"s390x"*) vdis="linux-s390x" ;;
            "ppc64le") vdis="linux-ppc64le" ;;
            "x86_64") vdis="linux-amd64" ;;
        esac
    fi
    [[ $(id -u) != "0" ]] && sudo="sudo"
}

install_go(){
    if [[ -z $install_version ]]; then
        echo "正在获取最新版golang..."
        count=0
        while :; do
            install_version=""
            if [[ $can_google == 0 ]]; then
                install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://go.dev/dl/ | grep -w downloadBox | grep src | grep -oE '[0-9]+\.[0-9]+\.?[0-9]*' | head -n 1)
            else
                install_version=$(curl -s --connect-timeout 15 -H 'Cache-Control: no-cache' https://github.com/golang/go/tags | grep releases/tag | grep -v rc | grep -v beta | grep -oE '[0-9]+\.[0-9]+\.?[0-9]*' | head -n 1)
            fi
            [[ ${install_version: -1} == '.' ]] && install_version=${install_version%?}
            if [[ -z $install_version ]]; then
                [[ $count -lt 3 ]] && color_echo $yellow "获取go版本号超时, 正在重试..." || { color_echo $red "\n获取go版本号失败!"; exit 1; }
            else
                break
            fi
            count=$((count+1))
        done
        echo "最新版golang: `color_echo $blue $install_version`"
    fi

    if [[ $force_mode == 0 && $(command -v go) ]]; then
        [[ "$(go version | awk '{print $3}' | grep -Eo '[0-9.]+')" == "$install_version" ]] && return
    fi

    file_name="go${install_version}。$vdis.tar.gz"
    temp_path=$(mktemp -d)
    curl -H 'Cache-Control: no-cache' -L "https://dl.google.com/go/$file_name" -o "$file_name"
    tar -C "$temp_path" -xzf "$file_name"
    if [[ $? != 0 ]]; then
        color_echo $yellow "\n解压失败! 正在重新下载..."
        rm -rf "$file_name"
        curl -H 'Cache-Control: no-cache' -L "https://dl.google.com/go/$file_name" -o "$file_name"
        tar -C "$temp_path" -xzf "$file_name"
        [[ $? != 0 ]] && { color_echo $yellow "\n解压失败!"; rm -rf "$temp_path" "$file_name"; exit 1; }
    fi
    [[ -e /usr/local/go ]] && $sudo rm -rf /usr/local/go
    $sudo mv "$temp_path/go" /usr/local/
    rm -rf "$temp_path" "$file_name"
}

install_updater(){
    if [[ $os == "Linux" ]]; then
        if [[ ! -e /usr/local/bin/goupdate || -z "$(cat /usr/local/bin/goupdate | grep '$@')" ]]; then
            echo "source <(curl -L https://go-install.netlify.app/install.sh) \$@" > /usr/local/bin/goupdate
            chmod +x /usr/local/bin/goupdate
        fi
    elif [[ $os == "Darwin" ]]; then
        if [[ ! -e $HOME/go/bin/goupdate || -z "$(cat $HOME/go/bin/goupdate | grep '$@')" ]]; then
            cat > "$HOME/go/bin/goupdate" << 'EOF'
#!/bin/zsh
source <(curl -L https://go-install.netlify.app/install.sh) $@
EOF
            chmod +x "$HOME/go/bin/goupdate"
        fi
    fi
}

main(){
    sys_arch
    check_network
    install_go
    setup_env
    setup_proxy
    install_updater
    echo -e "golang `color_echo $blue $install_version` 安装成功!"
}

main
