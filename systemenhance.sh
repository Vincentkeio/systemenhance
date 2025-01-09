#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用root权限运行此脚本！${NC}"
  exit 1
fi

# 定义操作系统类型
if command -v apt &>/dev/null; then
    os_type="deb"
elif command -v yum &>/dev/null; then
    os_type="rpm"
else
    os_type="unknown"
fi

# 安装软件包函数
install_packages() {
    local packages=("$@")
    if [ "$os_type" = "deb" ]; then
        apt install -y "${packages[@]}"
    elif [ "$os_type" = "rpm" ]; then
        yum install -y "${packages[@]}"
    else
        echo -e "${RED}不支持的操作系统类型${NC}"
        exit 1
    fi
}

# 检查并安装软件包
check_and_install() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            echo -e "${YELLOW}未检测到 $pkg，正在安装...${NC}"
            install_packages "$pkg"
        else
            echo -e "${GREEN}$pkg 已安装${NC}"
        fi
    done
}

# 获取系统信息
get_system_info() {
    echo -e "${BLUE}正在获取系统信息...${NC}"
    SYSTEM_NAME=$(lsb_release -is 2>/dev/null || cat /etc/os-release | grep "^NAME=" | cut -d= -f2 | tr -d '"')
    SYSTEM_VERSION=$(lsb_release -rs 2>/dev/null || cat /etc/os-release | grep "^VERSION_ID=" | cut -d= -f2 | tr -d '"')
    KERNEL_VERSION=$(uname -r)
    SYSTEM_ARCH=$(uname -m)
    echo -e "${GREEN}操作系统: $SYSTEM_NAME${NC}"
    echo -e "${GREEN}版本号: $SYSTEM_VERSION${NC}"
    echo -e "${GREEN}内核版本: $KERNEL_VERSION${NC}"
    echo -e "${GREEN}系统架构: $SYSTEM_ARCH${NC}"
}

# 更新系统
update_system() {
    echo -e "${BLUE}正在更新系统...${NC}"
    if [ "$os_type" = "deb" ]; then
        apt update && apt upgrade -y
    elif [ "$os_type" = "rpm" ]; then
        yum update -y
    else
        echo -e "${RED}未检测到 apt 或 yum，无法更新系统${NC}"
        exit 1
    fi
    echo -e "${GREEN}系统更新完成。${NC}"
}

# 检查并安装常用组件
install_common_packages() {
    echo -e "${BLUE}正在检查并安装常用组件：sudo, wget, curl, fail2ban, ufw...${NC}"
    check_and_install sudo wget curl fail2ban ufw
    echo -e "${GREEN}常用组件安装完成。${NC}"
}

# 配置网络优先级
configure_network_priority() {
    echo -e "${BLUE}正在配置网络优先级...${NC}"
    local_ipv4=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    external_ipv4=$(curl -s https://api.ipify.org)
    ipv6_address=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | grep -vE '^fe80|^::1' | head -n 1)

    echo -e "${GREEN}本地IPv4地址: $local_ipv4${NC}"
    echo -e "${GREEN}外网IPv4地址: $external_ipv4${NC}"
    if [ -z "$ipv6_address" ]; then
        echo -e "${YELLOW}本机无IPv6地址${NC}"
    else
        echo -e "${GREEN}本机IPv6地址: $ipv6_address${NC}"
    fi

    if ping6 -c 1 ipv6.google.com &>/dev/null; then
        echo -e "${GREEN}IPv6可用${NC}"
    else
        echo -e "${YELLOW}IPv6不可用${NC}"
    fi

    if ping -c 1 google.com &>/dev/null; then
        echo -e "${GREEN}IPv4可用${NC}"
    else
        echo -e "${YELLOW}IPv4不可用${NC}"
    fi

    echo -e "${BLUE}请选择网络优先级：${NC}"
    select choice in "IPv4优先" "IPv6优先" "取消"; do
        case $choice in
            "IPv4优先")
                if sysctl net.ipv6.conf.all.prefer_ipv4 >/dev/null 2>&1; then
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=1
                    echo "net.ipv6.conf.all.prefer_ipv4=1" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo -e "${GREEN}已设置IPv4优先${NC}"
                else
                    echo -e "${YELLOW}prefer_ipv4 参数不可用，请手动修改 /etc/gai.conf 配置文件。${NC}"
                    echo "建议设置："
                    echo "precedence ::ffff:0:0/96  100"
                    echo "precedence ::/0             150"
                fi
                break
                ;;
            "IPv6优先")
                if sysctl net.ipv6.conf.all.prefer_ipv4 >/dev/null 2>&1; then
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=0
                    echo "net.ipv6.conf.all.prefer_ipv4=0" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo -e "${GREEN}已设置IPv6优先${NC}"
                else
                    echo -e "${YELLOW}prefer_ipv4 参数不可用，请手动修改 /etc/gai.conf 配置文件。${NC}"
                    echo "建议设置："
                    echo "precedence ::ffff:0:0/96  100"
                    echo "precedence ::/0             150"
                fi
                break
                ;;
            "取消")
                echo -e "${YELLOW}取消设置${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# 配置SSH端口
configure_ssh_port() {
    echo -e "${BLUE}正在配置SSH端口...${NC}"
    current_port=$(grep -E "^#?Port " /etc/ssh/sshd_config | awk '{print $2}')
    if [ -z "$current_port" ]; then
        current_port=22
    fi
    echo -e "${GREEN}当前SSH端口: $current_port${NC}"

    read -p "是否需要修改SSH端口？(y/n): " modify_choice
    if [[ "$modify_choice" == "y" || "$modify_choice" == "Y" ]]; then
        read -p "请输入新的SSH端口号 (1-65535): " new_port
        if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
            sudo sed -i "s/^#?Port .*/Port $new_port/" /etc/ssh/sshd_config
            sudo systemctl restart sshd
            echo -e "${GREEN}SSH端口已修改为 $new_port${NC}"
        else
            echo -e "${RED}无效的端口号${NC}"
        fi
    else
        echo -e "${YELLOW}跳过SSH端口修改${NC}"
    fi
}

# 启用BBR
enable_bbr() {
    echo -e "${BLUE}正在启用BBR...${NC}"
    if grep -q "CONFIG_TCP_BBR" /boot/config-$(uname -r); then
        sudo modprobe tcp_bbr
        echo "tcp_bbr" | sudo tee -a /etc/modules-load.d/modules.conf > /dev/null
        sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null
        sudo sysctl -p
        echo -e "${GREEN}BBR已启用${NC}"
    else
        echo -e "${YELLOW}内核不支持BBR，请升级内核。${NC}"
    fi
}

# 清理系统垃圾
clean_system() {
    echo -e "${BLUE}正在清理系统垃圾...${NC}"
    if [ "$os_type" = "deb" ]; then
        apt clean
        apt autoclean
        apt autoremove -y
    elif [ "$os_type" = "rpm" ]; then
        yum clean all
        yum autoremove -y
    fi
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    echo -e "${GREEN}系统垃圾清理完成${NC}"
}

# 主程序
get_system_info
update_system
install_common_packages
configure_network_priority
configure_ssh_port
enable_bbr
clean_system

echo -e "${GREEN}系统优化完成！${NC}"
echo -e "${YELLOW}如果修改了SSH端口，请确保在SSH工具中更新端口号。${NC}"
echo -e "${YELLOW}如果启用了BBR，请重启系统以生效。${NC}"
