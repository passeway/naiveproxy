#!/bin/bash

# 安装必要的工具
apt-get install -y software-properties-common

# 添加 Golang 的 PPA
add-apt-repository -y ppa:longsleep/golang-backports

# 更新软件包列表
apt-get update

# 安装 Go
apt-get install -y golang-go

# 使用Go编译naive
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
