#!/bin/bash

# ANSI颜色码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 初始化变量
bbr_modified=false
ssh_port_changed=false
new_ssh_port=22

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用root权限运行此脚本！${NC}"
  exit 1
fi

# 提示用户开始操作
echo -e "${BLUE}开始执行系统优化脚本...${NC}"
echo

# 获取系统详细信息
get_system_info() {
    SYSTEM_NAME=""
    SYSTEM_CODENAME=""
    SYSTEM_VERSION=""
    KERNEL_VERSION=$(uname -r)
    SYSTEM_ARCH=$(uname -m)

    # 1. 尝试通过 /etc/os-release 获取系统信息
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        SYSTEM_NAME=$NAME
        SYSTEM_CODENAME=${VERSION_CODENAME:-}
        SYSTEM_VERSION=$VERSION
    fi

    # 2. 如果 /etc/os-release 没有提供信息，使用 lsb_release 命令
    if [[ -z "$SYSTEM_NAME" ]] && command -v lsb_release &>/dev/null; then
        SYSTEM_NAME=$(lsb_release -i | awk '{print $2}')
        SYSTEM_CODENAME=$(lsb_release -c | awk '{print $2}')
        SYSTEM_VERSION=$(lsb_release -r | awk '{print $2}')
    fi

    # 3. 如果 lsb_release 不可用，读取 /etc/issue 文件
    if [[ -z "$SYSTEM_NAME" ]] && [[ -f /etc/issue ]]; then
        SYSTEM_NAME=$(head -n 1 /etc/issue | awk '{print $1}')
        SYSTEM_CODENAME=$(head -n 1 /etc/issue | awk '{print $2}')
        SYSTEM_VERSION=$(head -n 1 /etc/issue | awk '{print $3}')
    fi

    # 4. 尝试通过 /etc/debian_version 获取 Debian 系统信息
    if [[ -z "$SYSTEM_NAME" ]] && [[ -f /etc/debian_version ]]; then
        SYSTEM_NAME="Debian"
        SYSTEM_CODENAME=$(cat /etc/debian_version)
        SYSTEM_VERSION=$SYSTEM_CODENAME
    fi

    # 5. 尝试使用 dpkg 获取系统信息
    if [[ -z "$SYSTEM_NAME" ]] && command -v dpkg &>/dev/null; then
        SYSTEM_NAME=$(dpkg --status lsb-release 2>/dev/null | grep "Package" | awk '{print $2}')
        SYSTEM_CODENAME=$(dpkg --status lsb-release 2>/dev/null | grep "Version" | awk '{print $2}')
        SYSTEM_VERSION=$SYSTEM_CODENAME
    fi

    # 6. 使用 hostnamectl 获取系统信息（适用于 systemd 系统）
    if [[ -z "$SYSTEM_NAME" ]] && command -v hostnamectl &>/dev/null; then
        SYSTEM_NAME=$(hostnamectl | grep "Operating System" | awk -F ' : ' '{print $2}' | awk '{print $1}')
        SYSTEM_CODENAME=$(hostnamectl | grep "Operating System" | awk -F ' : ' '{print $2}' | awk '{print $2}')
        SYSTEM_VERSION=$SYSTEM_CODENAME
    fi

    # 7. 使用 uname 获取内核信息
    if [[ -z "$KERNEL_VERSION" ]]; then
        KERNEL_VERSION=$(uname -r)
    fi

    # 8. 使用 /proc/version 获取内核信息
    if [[ -z "$KERNEL_VERSION" ]] && [[ -f /proc/version ]]; then
        KERNEL_VERSION=$(cat /proc/version | awk '{print $3}')
    fi

    # 9. 如果没有获取到系统信息，退出
    if [[ -z "$SYSTEM_NAME" || -z "$SYSTEM_VERSION" ]]; then
        echo -e "${RED}无法获取系统信息${NC}"
        exit 1
    fi
}

# 获取系统信息
get_system_info

# 显示系统详细信息
echo -e "${BLUE}系统信息：${NC}"
echo -e "操作系统: ${GREEN}$SYSTEM_NAME${NC}"
echo -e "版本号: ${GREEN}$SYSTEM_VERSION${NC}"
echo -e "代号: ${GREEN}$SYSTEM_CODENAME${NC}"
echo -e "内核版本: ${GREEN}$KERNEL_VERSION${NC}"
echo -e "系统架构: ${GREEN}$SYSTEM_ARCH${NC}"
echo

# 一、检查并安装常用组件
echo -e "${BLUE}正在检查并安装常用组件：sudo, wget, curl, fail2ban, ufw...${NC}"
echo

# 函数：安装软件包
install_package() {
    local package=$1
    if ! command -v "$package" &> /dev/null; then
        echo -e "${YELLOW}未检测到 $package，正在安装...${NC}"
        if command -v apt &> /dev/null; then
            apt update && apt install -y "$package"
        elif command -v yum &> /dev/null; then
            yum install -y "$package"
        else
            echo -e "${RED}未检测到 apt 或 yum，无法安装 $package${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}$package 已安装${NC}"
    fi
}

# 检查并安装 sudo
install_package sudo

# 检查并安装 wget
install_package wget

# 检查并安装 curl
install_package curl

# 检查并安装 fail2ban
install_package fail2ban

# 检查并安装 ufw
install_package ufw

echo -e "${GREEN}常用组件安装完成。${NC}"
echo

# 二、检测并设置网络优先级的功能模块
check_and_set_network_priority() {
    echo -e "${BLUE}现在开始IPv4/IPv6网络配置${NC}"
    echo

    # 获取本机IPv4地址
    ipv4_address=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    
    # 获取本机IPv6地址，过滤掉链路本地地址 (::1/128 和 fe80::)
    ipv6_address=$(ip -6 addr show | grep -oP '(?<=inet6\s)[0-9a-f:]+(?=/)' | grep -vE '^fe80|^::1' | head -n 1)

    # 显示IPv4和IPv6地址，或提示没有该地址
    if [ -z "$ipv4_address" ]; then
        echo -e "${YELLOW}本机无IPv4地址${NC}"
    else
        echo -e "本机IPv4地址: ${GREEN}$ipv4_address${NC}"
    fi

    if [ -z "$ipv6_address" ]; then
        echo -e "${YELLOW}本机无IPv6地址${NC}"
    else
        echo -e "本机IPv6地址: ${GREEN}$ipv6_address${NC}"
    fi

    # 判断IPv6是否有效，可以通过访问IPv6网站来验证
    echo -e "${BLUE}正在验证IPv6可用性...${NC}"
    if ping6 -c 1 ipv6.google.com &>/dev/null; then
        echo -e "${GREEN}IPv6可用，已成功连接到IPv6网络。${NC}"
        ipv6_valid=true
    else
        echo -e "${YELLOW}IPv6不可用，无法连接到IPv6网络。${NC}"
        ipv6_valid=false
    fi

    # 判断IPv4是否有效，可以通过访问IPv4网站来验证
    echo -e "${BLUE}正在验证IPv4可用性...${NC}"
    if ping -4 -c 1 google.com &>/dev/null; then
        echo -e "${GREEN}IPv4可用，已成功连接到IPv4网络。${NC}"
        ipv4_valid=true
    else
        echo -e "${YELLOW}IPv4不可用，无法连接到IPv4网络。${NC}"
        ipv4_valid=false
    fi

    # 修改 /etc/gai.conf 来调整优先级
    adjust_ipv4_ipv6_priority() {
        if [ "$1" == "IPv4优先" ]; then
            # 设置IPv4优先
            if ! grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
                echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
                echo -e "${GREEN}已设置IPv4优先，并且配置已永久生效。${NC}"
            else
                echo -e "${GREEN}IPv4优先配置已存在。${NC}"
            fi
        elif [ "$1" == "IPv6优先" ]; then
            # 移除IPv4优先设置
            sed -i '/^precedence ::ffff:0:0\/96  100/d' /etc/gai.conf
            echo -e "${GREEN}已设置IPv6优先，并且配置已永久生效。${NC}"
        fi
    }

    # 检测当前优先级设置
    current_preference="IPv6优先" # 默认
    if grep -q "^precedence ::ffff:0:0/96  100" /etc/gai.conf; then
        current_preference="IPv4优先"
    fi
    echo -e "当前系统的优先级设置是: ${GREEN}$current_preference${NC}"
    echo

    # 如果是双栈模式，提供选择优先级的选项
    if [ -n "$ipv4_address" ] && [ -n "$ipv6_address" ] && [ "$ipv6_valid" == true ] && [ "$ipv4_valid" == true ]; then
        echo -e "${BLUE}本机为双栈模式，您可以选择优先使用IPv4或IPv6。${NC}"
        echo -e "请选择优先使用的协议："
        select choice in "IPv4优先" "IPv6优先" "取消"; do
            case $choice in
                "IPv4优先")
                    echo -e "您选择了IPv4优先。"
                    # 设置IPv4优先并修改 /etc/gai.conf
                    adjust_ipv4_ipv6_priority "IPv4优先"
                    break
                    ;;
                "IPv6优先")
                    echo -e "您选择了IPv6优先。"
                    # 设置IPv6优先并修改 /etc/gai.conf
                    adjust_ipv4_ipv6_priority "IPv6优先"
                    break
                    ;;
                "取消")
                    echo -e "您选择了取消。"
                    break
                    ;;
                *)
                    echo -e "无效选择，请重新选择。"
                    ;;
            esac
        done
    else
        if [ "$ipv4_valid" == false ] && [ "$ipv6_valid" == true ]; then
            echo -e "${YELLOW}本机为IPv6 only模式，IPv4不可用。${NC}"
        elif [ "$ipv6_valid" == false ] && [ "$ipv4_valid" == true ]; then
            echo -e "${YELLOW}本机为IPv4 only模式，IPv6不可用。${NC}"
        else
            echo -e "${RED}本机既不可用IPv4，也不可用IPv6，请检查网络配置。${NC}"
        fi
    fi
}

# 调用功能模块
check_and_set_network_priority
echo

# 显示当前磁盘空间和 SWAP 配置
echo -e "${BLUE}当前磁盘空间：${NC}"
df -h
echo

echo -e "${BLUE}当前SWAP配置：${NC}"
swapon --show
echo

echo -e "${BLUE}SWAP详情：${NC}"
free -h
echo

# 三、管理 SWAP
manage_swap(){
    echo -e "${BLUE}当前内存和 SWAP 使用情况：${NC}"
    free -h
    echo

    echo -e "${BLUE}请选择操作：${NC}"
    echo "1) 将 SWAP 大小调整为指定值"
    echo "2) 不调整 SWAP"
    read -p "请输入选项 (1 或 按回车默认不调整): " swap_choice

    case "$swap_choice" in
        1)
            # 调整 SWAP 大小
            echo -e "${GREEN}开始调整 SWAP 大小...${NC}"
            read -p "请输入新的 SWAP 大小（单位MB）: " new_swap_size

            # 验证输入是否为正整数
            if ! [[ "$new_swap_size" =~ ^[0-9]+$ ]] || [ "$new_swap_size" -le 0 ]; then
                echo -e "${RED}错误：请输入一个有效的正整数大小（MB）。${NC}"
                return
            fi

            # 检测是否有SWAP文件
            swap_files=($(swapon --show=NAME,TYPE --noheadings | awk '$2=="file"{print $1}'))
            swap_partitions=($(swapon --show=NAME,TYPE --noheadings | awk '$2=="partition"{print $1}'))

            if [ "${#swap_files[@]}" -gt 0 ]; then
                # 如果有SWAP文件，调整SWAP文件大小
                echo -e "${GREEN}检测到以下 SWAP 文件：${NC}"
                for swap_file in "${swap_files[@]}"; do
                    echo -e " - ${GREEN}$swap_file${NC}"
                done
                selected_swap_file="${swap_files[0]}" # 选择第一个SWAP文件
                echo -e "${BLUE}正在调整 SWAP 文件 $selected_swap_file 大小为 ${new_swap_size} MB...${NC}"

                # 禁用 SWAP 文件
                swapoff "$selected_swap_file"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法禁用 SWAP 文件 $selected_swap_file。${NC}"
                    return
                fi

                # 删除 SWAP 文件
                rm -f "$selected_swap_file"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法删除 SWAP 文件 $selected_swap_file。${NC}"
                    return
                fi

                # 创建新的 SWAP 文件
                fallocate -l "${new_swap_size}M" "$selected_swap_file" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo -e "${BLUE}fallocate 不可用，使用 dd 创建 SWAP 文件...${NC}"
                    dd if=/dev/zero bs=1M count="$new_swap_size" of="$selected_swap_file" status=progress
                    if [ $? -ne 0 ]; then
                        echo -e "${RED}错误：无法创建 SWAP 文件 $selected_swap_file。${NC}"
                        return
                    fi
                fi

                chmod 600 "$selected_swap_file"
                mkswap "$selected_swap_file"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法格式化 SWAP 文件 $selected_swap_file。${NC}"
                    return
                fi

                swapon "$selected_swap_file"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法启用 SWAP 文件 $selected_swap_file。${NC}"
                    return
                fi

                # 确保 /etc/fstab 中的 SWAP 配置正确
                if ! grep -q "^$selected_swap_file\s" /etc/fstab; then
                    echo "$selected_swap_file none swap defaults 0 0" >> /etc/fstab
                fi

                echo -e "${GREEN}SWAP 文件 $selected_swap_file 已成功调整为 ${new_swap_size} MB。${NC}"
            elif [ "${#swap_partitions[@]}" -gt 0 ]; then
                # 如果有SWAP分区，调整SWAP分区大小
                echo -e "${YELLOW}检测到以下 SWAP 分区：${NC}"
                for partition in "${swap_partitions[@]}"; do
                    echo -e " - ${GREEN}$partition${NC}"
                done

                selected_swap_partition="${swap_partitions[0]}" # 选择第一个SWAP分区
                echo -e "${BLUE}正在调整 SWAP 分区 $selected_swap_partition 大小为 ${new_swap_size} MB...${NC}"

                # 禁用 SWAP 分区
                swapoff "$selected_swap_partition"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法禁用 SWAP 分区 $selected_swap_partition。${NC}"
                    return
                fi

                # 获取磁盘设备和分区编号
                disk=$(lsblk -no PKNAME "$selected_swap_partition")
                partition_number=$(lsblk -no PARTNUM "$selected_swap_partition")

                # 检查 parted 是否安装
                if ! command -v parted &>/dev/null; then
                    echo -e "${RED}错误：未安装 parted 工具。请手动安装 parted 并重试。${NC}"
                    return
                fi

                # 使用 parted 调整分区大小
                echo -e "${BLUE}使用 parted 调整分区大小...${NC}"
                parted /dev/"$disk" --script resizepart "$partition_number" "${new_swap_size}MB"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法调整分区大小 $selected_swap_partition。请手动检查分区状态。${NC}"
                    return
                fi

                # 重新格式化为 SWAP 分区
                echo -e "${BLUE}正在格式化分区 $selected_swap_partition 为 SWAP...${NC}"
                mkswap "$selected_swap_partition"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法格式化 SWAP 分区 $selected_swap_partition。${NC}"
                    return
                fi

                # 启用 SWAP 分区
                swapon "$selected_swap_partition"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法启用 SWAP 分区 $selected_swap_partition。${NC}"
                    return
                fi

                # 确保 /etc/fstab 中的 SWAP 配置正确
                if ! grep -q "^$selected_swap_partition\s" /etc/fstab; then
                    echo "$selected_swap_partition none swap defaults 0 0" >> /etc/fstab
                fi

                echo -e "${GREEN}SWAP 分区 $selected_swap_partition 已成功调整为 ${new_swap_size} MB。${NC}"
            else
                echo -e "${YELLOW}未检测到 SWAP 文件或 SWAP 分区。${NC}"
            fi

            # 显示新的 SWAP 信息
            echo -e "${BLUE}调整后的内存和 SWAP 使用情况：${NC}"
            free -h
            echo

            # 提示按回车键继续
            read -p "按回车键继续..." dummy
            ;;
        *)
            # 不调整 SWAP
            echo -e "${YELLOW}您选择不调整 SWAP。${NC}"
            ;;
    esac
}

# 调用 SWAP 管理函数
manage_swap
echo

# 四、设置时区
set_timezone(){
    echo -e "${BLUE}当前时区设置为: $(timedatectl | grep "Time zone" | awk '{print $3}')${NC}"
    echo -e "${BLUE}可用的时区列表: ${NC}"
    timedatectl list-timezones | less

    read -p "请输入您要设置的时区（例如：Asia/Shanghai）: " timezone

    if timedatectl list-timezones | grep -qw "$timezone"; then
        timedatectl set-timezone "$timezone"
        echo -e "${GREEN}时区已成功设置为 $timezone。${NC}"
    else
        echo -e "${RED}无效的时区输入。请重新运行脚本并输入正确的时区。${NC}"
    fi
}

# 调用设置时区函数
set_timezone
echo

# 五、修改SSH端口
change_ssh_port(){
    current_ssh_port=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')

    echo -e "${BLUE}当前SSH端口: ${GREEN}$current_ssh_port${NC}"
    read -p "请输入新的SSH端口号（默认保持当前端口: $current_ssh_port）: " new_port

    # 如果用户按回车，则保持当前端口
    if [[ -z "$new_port" ]]; then
        echo -e "${YELLOW}保持当前SSH端口: $current_ssh_port${NC}"
        return
    fi

    # 验证端口号是否为有效的数字且在1-65535之间
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -le 0 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${RED}错误：请输入一个有效的端口号（1-65535）。${NC}"
        return
    fi

    # 检查端口是否被占用
    if ss -tuln | grep -q ":$new_port "; then
        echo -e "${RED}错误：端口 $new_port 已被占用。${NC}"
        return
    fi

    # 修改SSH配置文件
    sed -i "s/^#Port .*/Port $new_port/" /etc/ssh/sshd_config
    sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config

    # 允许新端口通过防火墙
    if command -v ufw &>/dev/null; then
        ufw allow "$new_port"/tcp
        ufw delete allow "$current_ssh_port"/tcp
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$new_port"/tcp
        firewall-cmd --permanent --remove-port="$current_ssh_port"/tcp
        firewall-cmd --reload
    fi

    # 重启SSH服务
    systemctl restart sshd

    echo -e "${GREEN}SSH端口已成功更改为 $new_port。${NC}"
    ssh_port_changed=true
}

# 调用修改SSH端口函数
change_ssh_port
echo

# 六、启用防火墙
enable_firewall(){
    echo -e "${BLUE}正在配置防火墙...${NC}"

    if command -v ufw &>/dev/null; then
        # 启用UFW
        echo -e "${GREEN}启用UFW防火墙...${NC}"
        ufw enable
        # 默认拒绝入站，允许出站
        ufw default deny incoming
        ufw default allow outgoing
        # 允许SSH端口
        if [ "$ssh_port_changed" = true ]; then
            ufw allow "$new_port"/tcp
        else
            ufw allow "$current_ssh_port"/tcp
        fi
        echo -e "${GREEN}UFW防火墙已启用并配置完毕。${NC}"
    elif command -v firewall-cmd &>/dev/null; then
        # 启用firewalld
        echo -e "${GREEN}启用firewalld防火墙...${NC}"
        systemctl start firewalld
        systemctl enable firewalld
        # 默认拒绝入站，允许出站
        firewall-cmd --permanent --set-default-zone=public
        # 允许SSH端口
        if [ "$ssh_port_changed" = true ]; then
            firewall-cmd --permanent --add-port="$new_port"/tcp
        else
            firewall-cmd --permanent --add-port="$current_ssh_port"/tcp
        fi
        firewall-cmd --reload
        echo -e "${GREEN}firewalld防火墙已启用并配置完毕。${NC}"
    else
        echo -e "${YELLOW}未检测到ufw或firewalld防火墙工具，跳过防火墙配置。${NC}"
    fi
}

# 调用启用防火墙函数
enable_firewall
echo

# 七、启用 Fail2Ban
enable_fail2ban(){
    echo -e "${BLUE}正在配置 Fail2Ban...${NC}"
    
    if [ -f /etc/fail2ban/jail.local ]; then
        echo -e "${YELLOW}发现已存在 /etc/fail2ban/jail.local 配置文件，跳过创建。${NC}"
    else
        # 创建基本的 jail.local 配置
        cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
bantime  = 10m
findtime  = 10m
maxretry = 5

[sshd]
enabled = true
port    = $(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
EOL
    fi

    # 重启 Fail2Ban 服务
    systemctl restart fail2ban
    systemctl enable fail2ban

    echo -e "${GREEN}Fail2Ban 已成功启用并配置。${NC}"
}

# 调用启用 Fail2Ban 函数
enable_fail2ban
echo

# 八、启用 BBR+FQ
enable_bbr_fq() {
    echo -e "${BLUE}正在启用 BBR 和 FQ 加速方案...${NC}"

    # 启用 BBR
    sysctl -w net.ipv4.tcp_congestion_control=bbr

    # 启用 FQ（FQ是BBR的配套方案）
    sysctl -w net.core.default_qdisc=fq

    # 永久启用 BBR 和 FQ（在 /etc/sysctl.conf 中添加配置）
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi

    # 重新加载 sysctl 配置
    sysctl -p

    echo -e "${GREEN}BBR 和 FQ 已成功启用！${NC}"
}

# 检查是否已启用 BBR
check_bbr() {
    sysctl net.ipv4.tcp_congestion_control | grep -q 'bbr'
    return $?
}

# 显示当前的 BBR 配置和加速方案
show_bbr_info() {
    # 显示当前的 TCP 拥塞控制算法
    echo -e "${BLUE}当前系统的 TCP 拥塞控制算法: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${NC}"
    
    # 显示当前的默认队列调度器
    echo -e "${BLUE}当前系统的默认队列调度器: $(sysctl net.core.default_qdisc | awk '{print $3}')${NC}"
}

# 主程序
echo -e "${BLUE}检测是否启用 BBR 加速...${NC}"
echo

# 检查 BBR 是否已经启用
check_bbr
if [ $? -eq 0 ]; then
    echo -e "${GREEN}BBR 已启用，当前配置如下：${NC}"
    show_bbr_info
    echo -e "${GREEN}BBR 已经启用，跳过启用过程，继续执行脚本的其他部分...${NC}"
else
    # 显示当前 BBR 配置和加速方案
    show_bbr_info

    # 询问用户是否启用 BBR+FQ
    echo -e "${BLUE}BBR 未启用，您可以选择启用 BBR+FQ 加速方案：${NC}"
    echo "1. 启用 BBR+FQ"
    echo "2. 不启用，跳过"
    read -p "请输入您的选择 (1 或 2): " choice

    if [[ "$choice" == "1" ]]; then
        # 用户选择启用 BBR+FQ
        enable_bbr_fq
        echo -e "${YELLOW}BBR+FQ 已启用，您需要重启系统才能生效。${NC}"
        # 标记 BBR 被修改
        bbr_modified=true
    elif [[ "$choice" == "2" ]]; then
        # 用户选择不启用
        echo -e "${YELLOW}维持当前配置，跳过 BBR 加速启用部分，继续执行脚本的其他部分。${NC}"
    else
        echo -e "${YELLOW}无效的选择，跳过此部分。${NC}"
    fi
fi

# 继续执行脚本的后续部分...
echo -e "${GREEN}继续执行脚本的其他部分...${NC}"
echo

# 九、清理系统垃圾
echo -e "${BLUE}开始清理系统垃圾...${NC}"
echo

# 对于基于 Debian/Ubuntu 的系统，清理 apt 缓存
if command -v apt &> /dev/null; then
  echo -e "${BLUE}正在清理 APT 缓存...${NC}"
  apt clean
  apt autoclean
  apt autoremove -y
fi

# 对于基于 CentOS/RHEL 的系统，清理 YUM 缓存
if command -v yum &> /dev/null; then
  echo -e "${BLUE}正在清理 YUM 缓存...${NC}"
  yum clean all
  yum autoremove -y
fi

# 清理临时文件
echo -e "${BLUE}正在清理临时文件...${NC}"
# 使用 find 命令删除超过7天的临时文件
find /tmp -type f -mtime +7 -exec rm -f {} \;
find /var/tmp -type f -mtime +7 -exec rm -f {} \;

echo -e "${GREEN}系统垃圾清理完成！${NC}"
echo

# 十、清理日志文件（用户选择清理时间范围）
echo -e "${BLUE}请选择要清理的日志文件时间范围：${NC}"
echo "1) 清除一周内的日志"
echo "2) 清除一月内的日志"
echo "3) 清除半年的日志"
echo "4) 清除所有日志"
echo "5) 不用清理"

read -p "请输入选项 (1/2/3/4/5): " log_choice

case $log_choice in
  1)
    echo -e "${BLUE}正在清除一周内的日志...${NC}"
    find /var/log -type f -name '*.log' -mtime +7 -exec rm -f {} \;
    ;;
  2)
    echo -e "${BLUE}正在清除一月内的日志...${NC}"
    find /var/log -type f -name '*.log' -mtime +30 -exec rm -f {} \;
    ;;
  3)
    echo -e "${BLUE}正在清除半年的日志...${NC}"
    find /var/log -type f -name '*.log' -mtime +180 -exec rm -f {} \;
    ;;
  4)
    echo -e "${BLUE}正在清除所有日志...${NC}"
    find /var/log -type f -name '*.log' -exec rm -f {} \;
    ;;
  5)
    echo -e "${YELLOW}不清理日志文件，跳过此步骤。${NC}"
    ;;
  *)
    echo -e "${YELLOW}无效选项，跳过清理日志文件。${NC}"
    ;;
esac

echo -e "${GREEN}日志清理完成！${NC}"
echo

# 十一、系统优化完成提示
echo -e "${GREEN}系统优化完成！${NC}"
echo

echo -e "本次优化包括："
echo -e "1) ${GREEN}更新了系统并安装了常用组件（如 sudo, wget, curl, fail2ban, ufw）。${NC}"
echo -e "2) ${GREEN}检测并配置了IPv4/IPv6环境，确保网络访问正常。${NC}"
echo -e "3) ${GREEN}设置了时区。${NC}"
echo -e "4) ${GREEN}修改了SSH端口（如果选择了修改）。${NC}"
echo -e "5) ${GREEN}启用了防火墙并配置了常用端口，特别是SSH服务端口。${NC}"
echo -e "6) ${GREEN}启用了 Fail2Ban 防护，增强了系统安全性。${NC}"
echo -e "7) ${GREEN}根据您的选择，已调整或配置了 SWAP 大小。${NC}"
echo -e "8) ${GREEN}根据您的选择，已设置BBR。${NC}"
echo -e "9) ${GREEN}清理了系统垃圾文件和临时文件。${NC}"
echo -e "10) ${GREEN}根据您的选择，已清理了不需要的系统日志文件。${NC}"

# 询问是否重启
if [ "$bbr_modified" = true ]; then
    echo -e "${YELLOW}刚才修改了BBR设置，需要重启后才能生效。${NC}"
    read -p "是否现在重启系统？(y/n): " reboot_choice
    if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
        echo -e "${GREEN}正在重启系统...${NC}"
        reboot
    else
        echo -e "${YELLOW}您选择稍后手动重启系统。${NC}"
    fi
elif [ "$ssh_port_changed" = true ]; then
    echo -e "${YELLOW}修改了SSH端口，请确保在SSH客户端中使用新的端口号连接。${NC}"
fi

echo -e "${GREEN}所有操作已完成，系统已经优化并增强了安全性！${NC}"
echo -e "${YELLOW}如果修改了SSH端口，记得在SSH工具上修改为新的端口，否则无法连接。${NC}"
