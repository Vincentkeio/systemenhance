#!/bin/bash

# ANSI颜色码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无色

# 初始化变量
bbr_modified=false

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
            apt install -y "$package"
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
manage_swap() {
    echo -e "${BLUE}请选择操作：${NC}"
    echo "1) 增加 SWAP"
    echo "2) 减少 SWAP"
    echo "3) 不调整 SWAP"
    read -p "请输入选项 (1/2/3): " swap_choice

    case $swap_choice in
      1)
        # 增加 SWAP
        increase_swap
        ;;
      2)
        # 减少 SWAP
        decrease_swap
        ;;
      3)
        # 不调整 SWAP
        echo -e "${YELLOW}您选择不调整 SWAP。${NC}"
        ;;
      *)
        echo -e "${YELLOW}无效选项，退出程序。${NC}"
        ;;
    esac
}

# 函数：增加 SWAP
increase_swap() {
    read -p "请输入增加的 SWAP 大小 (单位 MB): " swap_add_size
    # 验证输入是否为正整数
    if ! [[ "$swap_add_size" =~ ^[0-9]+$ ]] || [ "$swap_add_size" -le 0 ]; then
        echo -e "${RED}错误：请输入一个有效的正整数大小（MB）。${NC}"
        return
    fi

    echo -e "${BLUE}正在增加 $swap_add_size MB 的 SWAP...${NC}"

    # 获取所有 SWAP 文件
    swap_files=($(swapon --show=NAME,TYPE --noheadings | awk '$2=="file"{print $1}'))

    if [ "${#swap_files[@]}" -eq 0 ]; then
        # 如果没有 SWAP 文件，创建一个新的
        new_swap_file="/swapfile"
        echo -e "${YELLOW}未检测到现有的 SWAP 文件，将创建新的 SWAP 文件：$new_swap_file${NC}"
    else
        # 选择第一个 SWAP 文件进行扩展
        new_swap_file="${swap_files[0]}"
        echo -e "${GREEN}将增加现有 SWAP 文件：$new_swap_file${NC}"
    fi

    # 创建或扩展 SWAP 文件
    if [ ! -f "$new_swap_file" ]; then
        # 创建新的 SWAP 文件
        echo -e "${BLUE}正在创建新的 SWAP 文件 $new_swap_file...${NC}"
        fallocate -l "${swap_add_size}M" "$new_swap_file" 2>/dev/null
        if [ $? -ne 0 ]; then
            # 如果 fallocate 不可用，使用 dd
            echo -e "${BLUE}fallocate 不可用，使用 dd 创建 SWAP 文件...${NC}"
            dd if=/dev/zero bs=1M count="$swap_add_size" of="$new_swap_file" status=progress
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：无法创建 SWAP 文件 $new_swap_file${NC}"
                return
            fi
        fi
    else
        # 扩展现有 SWAP 文件
        echo -e "${BLUE}正在扩展现有 SWAP 文件 $new_swap_file...${NC}"
        # 禁用 SWAP 文件
        swapoff "$new_swap_file" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}错误：无法禁用 SWAP 文件 $new_swap_file${NC}"
            return
        fi

        # 扩展 SWAP 文件
        fallocate -l "+${swap_add_size}M" "$new_swap_file" 2>/dev/null
        if [ $? -ne 0 ]; then
            # 如果 fallocate 不可用，使用 dd
            current_size_mb=$(stat -c%s "$new_swap_file")
            current_size_mb=$((current_size_mb / 1048576))
            echo -e "${BLUE}fallocate 不可用，使用 dd 扩展 SWAP 文件...${NC}"
            dd if=/dev/zero bs=1M count="$swap_add_size" of="$new_swap_file" seek="$current_size_mb" conv=notrunc status=progress
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：无法扩展 SWAP 文件 $new_swap_file${NC}"
                return
            fi
        fi
    fi

    # 设置正确的权限
    chmod 600 "$new_swap_file"

    # 格式化 SWAP 文件
    mkswap "$new_swap_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：无法格式化 SWAP 文件 $new_swap_file。${NC}"
        return
    fi

    # 启用 SWAP 文件
    swapon "$new_swap_file" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：无法启用 SWAP 文件 $new_swap_file。${NC}"
        return
    fi

    # 确保 SWAP 文件在 /etc/fstab 中
    if ! grep -q "^$new_swap_file\s" /etc/fstab; then
        echo "$new_swap_file none swap sw 0 0" >> /etc/fstab
    fi

    echo -e "${GREEN}已成功增加 $swap_add_size MB 的 SWAP。${NC}"
}

# 函数：减少 SWAP
decrease_swap() {
    read -p "请输入减少的 SWAP 大小 (单位 MB): " swap_reduce_size
    # 验证输入是否为正整数
    if ! [[ "$swap_reduce_size" =~ ^[0-9]+$ ]] || [ "$swap_reduce_size" -le 0 ]; then
        echo -e "${RED}错误：请输入一个有效的正整数大小（MB）。${NC}"
        return
    fi

    echo -e "${BLUE}正在减少 $swap_reduce_size MB 的 SWAP...${NC}"

    # 获取所有 SWAP 文件，按大小从大到小排序
    swap_info=$(swapon --show=NAME,SIZE --noheadings | awk '$1 ~ /^\/swap/{print $1 " " $2}' | sort -k2 -nr)
    swap_files=($(echo "$swap_info" | awk '{print $1}'))
    swap_sizes=($(echo "$swap_info" | awk '{print $2}'))

    if [ "${#swap_files[@]}" -eq 0 ]; then
        echo -e "${RED}未检测到任何 SWAP 文件，无法减少 SWAP。${NC}"
        return
    fi

    total_swap_reduction=0

    for i in "${!swap_files[@]}"; do
        swap_file="${swap_files[$i]}"
        current_swap_size="${swap_sizes[$i]}" # e.g., "512M"

        # 将 SWAP 大小转换为整数 MB
        current_swap_size_mb=$(echo "$current_swap_size" | sed 's/M//')

        if [ "$current_swap_size_mb" -le 0 ]; then
            continue
        fi

        if [ "$swap_reduce_size" -le 0 ]; then
            break
        fi

        if [ "$current_swap_size_mb" -ge "$swap_reduce_size" ]; then
            # 可以在当前 SWAP 文件中减少
            new_swap_size_mb=$((current_swap_size_mb - swap_reduce_size))

            echo -e "${GREEN}正在减少 SWAP 文件 $swap_file 大小为 $swap_reduce_size MB...${NC}"

            # 禁用当前 SWAP 文件
            swapoff "$swap_file" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：无法禁用 SWAP 文件 $swap_file。${NC}"
                continue
            fi

            if [ "$new_swap_size_mb" -le 0 ]; then
                # 完全禁用 SWAP 文件
                echo -e "${YELLOW}将完全禁用并删除 SWAP 文件 $swap_file...${NC}"
                rm -f "$swap_file"
                # 从 /etc/fstab 中移除
                sed -i "/^$swap_file\s/d" /etc/fstab
            else
                # 调整 SWAP 文件大小
                echo -e "${BLUE}正在调整 SWAP 文件 $swap_file 大小为 $new_swap_size_mb MB...${NC}"
                fallocate -l "${new_swap_size_mb}M" "$swap_file" 2>/dev/null
                if [ $? -ne 0 ]; then
                    # fallocate 不可用，使用 dd
                    echo -e "${BLUE}fallocate 不可用，使用 dd 调整 SWAP 文件大小...${NC}"
                    dd if=/dev/zero bs=1M count="$new_swap_size_mb" of="$swap_file" conv=notrunc status=progress
                    if [ $? -ne 0 ]; then
                        echo -e "${RED}错误：无法调整 SWAP 文件大小 $swap_file。${NC}"
                        continue
                    fi
                fi

                # 设置正确的权限
                chmod 600 "$swap_file"

                # 格式化 SWAP 文件
                mkswap "$swap_file" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法格式化 SWAP 文件 $swap_file。${NC}"
                    continue
                fi

                # 启用 SWAP 文件
                swapon "$swap_file" 2>/dev/null
                if [ $? -ne 0 ]; then
                    echo -e "${RED}错误：无法启用 SWAP 文件 $swap_file。${NC}"
                    continue
                fi

                echo -e "${GREEN}已成功减少 SWAP 文件 $swap_file 大小为 ${new_swap_size_mb} MB。${NC}"
            fi

            # 更新总减少的 SWAP
            total_swap_reduction=$((total_swap_reduction + swap_reduce_size))
            break
        else
            # 完全禁用当前 SWAP 文件
            echo -e "${YELLOW}将完全禁用并删除 SWAP 文件 $swap_file...${NC}"
            swapoff "$swap_file" 2>/dev/null
            if [ $? -ne 0 ]; then
                echo -e "${RED}错误：无法禁用 SWAP 文件 $swap_file。${NC}"
                continue
            fi
            rm -f "$swap_file"
            sed -i "/^$swap_file\s/d" /etc/fstab
            total_swap_reduction=$((total_swap_reduction + current_swap_size_mb))
            swap_reduce_size=$((swap_reduce_size - current_swap_size_mb))
        fi
    done

    # 检查是否达到用户要求的减少量
    if [ "$total_swap_reduction" -ge "$swap_reduce_size" ]; then
        echo -e "${GREEN}已成功减少 $total_swap_reduction MB 的 SWAP。${NC}"
    else
        echo -e "${YELLOW}警告：仅减少了 $total_swap_reduction MB 的 SWAP，无法满足减少 $swap_reduce_size MB 的要求。${NC}"
    fi
}

# 调用 SWAP 管理函数
manage_swap
echo

# 显示 SWAP 修改后的配置和详情
echo -e "${BLUE}修改后的SWAP配置：${NC}"
swapon --show
echo

echo -e "${BLUE}修改后的SWAP详情：${NC}"
free -h
echo

# 四、检查并处理 SWAP 分区
handle_swap_partitions() {
    # 获取所有 SWAP 分区
    swap_partitions=($(swapon --show=NAME,TYPE --noheadings | awk '$2=="partition"{print $1}'))

    if [ "${#swap_partitions[@]}" -eq 0 ]; then
        echo -e "${GREEN}未检测到 SWAP 分区。${NC}"
    else
        echo -e "${YELLOW}检测到以下 SWAP 分区：${NC}"
        for partition in "${swap_partitions[@]}"; do
            echo -e " - ${GREEN}$partition${NC}"
        done
        echo -e "${YELLOW}由于 SWAP 分区无法通过脚本自动调整大小，请手动管理这些分区。${NC}"
        echo -e "${YELLOW}以下是手动调整 SWAP 分区大小的建议步骤：${NC}"
        echo -e "1. 备份重要数据。"
        echo -e "2. 禁用 SWAP 分区：sudo swapoff /dev/your_swap_partition"
        echo -e "3. 使用分区工具（如 fdisk, parted）调整分区大小。"
        echo -e "4. 重新格式化为 SWAP 分区：sudo mkswap /dev/your_swap_partition"
        echo -e "5. 启用 SWAP 分区：sudo swapon /dev/your_swap_partition"
        echo -e "6. 确保 /etc/fstab 中的 SWAP 分区配置正确。"
    fi
}

# 调用 SWAP 分区处理函数
handle_swap_partitions
echo

# 五、检查SSH服务是否安装并运行
check_ssh_service() {
  echo -e "${BLUE}现在开始检测SSH服务...${NC}"
  echo

  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo -e "${YELLOW}未检测到SSH服务。${NC}"
    read -p "是否需要安装并设置SSH服务并更改端口号（y/n）？" choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
      install_ssh
      configure_ssh_port
    else
      echo -e "${YELLOW}跳过SSH服务设置，继续执行其他任务。${NC}"
    fi
  else
    configure_ssh_port
  fi
}

# 安装并启动SSH服务
install_ssh() {
  if [[ "$SYSTEM_NAME" == "Ubuntu" || "$SYSTEM_NAME" == "Debian" ]]; then
    # Ubuntu/Debian 系统
    if ! systemctl is-active --quiet ssh; then
      echo -e "${YELLOW}SSH服务未安装或未启动，正在安装SSH服务...${NC}"
      apt update && apt install -y openssh-server
      systemctl enable ssh
      systemctl start ssh
      echo -e "${GREEN}SSH服务已安装并启动！${NC}"
    fi
  elif [[ "$SYSTEM_NAME" == "CentOS" || "$SYSTEM_NAME" == "RedHat" || "$SYSTEM_NAME" == "RHEL" ]]; then
    # CentOS/RHEL 系统
    if ! systemctl is-active --quiet sshd; then
      echo -e "${YELLOW}SSH服务未安装或未启动，正在安装SSH服务...${NC}"
      yum install -y openssh-server
      systemctl enable sshd
      systemctl start sshd
      echo -e "${GREEN}SSH服务已安装并启动！${NC}"
    fi
  else
    echo -e "${RED}无法识别的操作系统：$SYSTEM_NAME，无法处理SSH服务。${NC}"
    return  # 跳过当前功能块，继续执行后续部分
  fi
}

# 配置SSH端口
configure_ssh_port() {
  # 获取当前SSH端口
  current_port=$(grep -E "^#?Port " /etc/ssh/sshd_config | awk '{print $2}')
  if [ -z "$current_port" ]; then
    current_port=22 # 如果未设置Port，默认值为22
  fi

  echo -e "当前SSH端口为: ${GREEN}$current_port${NC}"

  # 询问用户是否需要修改SSH端口
  read -p "是否需要修改SSH端口？(y/n): " modify_choice
  if [[ "$modify_choice" == "y" || "$modify_choice" == "Y" ]]; then
    # 提示用户输入新的SSH端口
    read -p "请输入新的SSH端口号 (1-65535): " new_port

    # 验证端口号是否有效
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      echo -e "${RED}错误：请输入一个有效的端口号（1-65535）！${NC}"
      return  # 跳过当前功能块，继续执行后续部分
    fi

    # 检查新端口是否已被使用
    if ss -tuln | grep -q ":$new_port "; then
      echo -e "${RED}错误：端口 $new_port 已被占用，请选择其他端口。${NC}"
      return
    fi

    # 修改sshd_config文件
    ssh_config_file="/etc/ssh/sshd_config"
    if [ -f "$ssh_config_file" ]; then
      # 备份配置文件
      cp "$ssh_config_file" "${ssh_config_file}.bak"

      # 更新端口配置
      if grep -qE "^#?Port " "$ssh_config_file"; then
        sed -i "s/^#\?Port .*/Port $new_port/" "$ssh_config_file"
      else
        echo "Port $new_port" >> "$ssh_config_file"
      fi

      echo -e "SSH配置已更新，新的端口号为: ${GREEN}$new_port${NC}"
    else
      echo -e "${RED}错误：找不到SSH配置文件 $ssh_config_file${NC}"
      return  # 跳过当前功能块，继续执行后续部分
    fi

    # 检查修改后的配置是否生效
    current_port_in_ssh_config=$(grep "^Port " "$ssh_config_file" | awk '{print $2}')

    if [ "$current_port_in_ssh_config" -eq "$new_port" ]; then
      echo -e "SSH端口修改成功，新端口为 ${GREEN}$new_port${NC}"
    else
      echo -e "${RED}错误：SSH端口修改失败，请检查配置。${NC}"
      return  # 跳过当前功能块，继续执行后续部分
    fi
  else
    echo -e "${YELLOW}跳过SSH端口修改，继续执行其他任务。${NC}"
  fi

  # 检查SSH服务是否已正常启用
  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo -e "${YELLOW}警告：SSH服务未正常启用，无法继续检查新端口是否生效。${NC}"
    return  # 跳过当前功能块，继续执行后续部分
  else
    echo -e "${GREEN}SSH服务已正常启用，继续检查新端口是否生效。${NC}"
  fi

  # 检查新端口是否在防火墙中开放
  check_firewall "$new_port" "$current_port"
}

# 检查防火墙并开放新端口
check_firewall() {
  local new_port=$1
  local old_port=$2

  # 如果新端口为空，则默认使用22
  if [ -z "$new_port" ]; then
    new_port=22
  fi

  if command -v ufw >/dev/null 2>&1; then
    # ufw防火墙启用检查
    if ! ufw status | grep -q "Status: active"; then
      echo -e "${YELLOW}防火墙未启用，且新端口未被防火墙阻拦。${NC}"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! ufw status | grep -q "$new_port/tcp"; then
        ufw allow "$new_port/tcp"
        echo -e "${GREEN}防火墙已启用，新端口已添加放行规则。${NC}"
      else
        echo -e "${GREEN}新端口已开放，防火墙规则已放行该端口。${NC}"
      fi
    fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # firewalld防火墙启用检查
    if ! systemctl is-active --quiet firewalld; then
      echo -e "${YELLOW}防火墙未启用，且新端口未被防火墙阻拦。${NC}"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! firewall-cmd --list-all | grep -q "$new_port/tcp"; then
        firewall-cmd --permanent --add-port="$new_port/tcp"
        firewall-cmd --reload
        echo -e "${GREEN}防火墙已启用，新端口已添加放行规则。${NC}"
      else
        echo -e "${GREEN}新端口已开放，防火墙规则已放行该端口。${NC}"
      fi
    fi
  else
    echo -e "${YELLOW}警告：未检测到受支持的防火墙工具，请手动开放新端口 $new_port。${NC}"
    echo -e "${YELLOW}防火墙未启用，且新端口未被防火墙阻拦。${NC}"
  fi

  # 检查新端口是否成功开放
  if ! ss -tuln | grep -q ":$new_port "; then
    echo -e "${RED}错误：新端口 $new_port 未成功开放，执行修复步骤...${NC}"
    
    # 执行修复步骤：重新加载配置并重启SSH服务
    echo -e "执行 ${GREEN}systemctl daemon-reload${NC}"
    systemctl daemon-reload

    echo -e "执行 ${GREEN}/etc/init.d/ssh restart${NC}"
    /etc/init.d/ssh restart

    echo -e "执行 ${GREEN}systemctl restart ssh${NC}"
    systemctl restart ssh

    # 再次检查新端口是否生效
    echo -e "检查新端口是否生效..."
    ss -tuln | grep -q ":$new_port "

    # 即使修复失败，也只提示，不退出，跳过当前功能块
    if ! ss -tuln | grep -q ":$new_port "; then
      echo -e "${YELLOW}警告：修复后新端口 $new_port 仍未成功开放，跳过该功能块，继续后续任务。${NC}"
    else
      echo -e "${GREEN}新端口 $new_port 已成功开放。${NC}"
    fi
  else
    echo -e "${GREEN}新端口 $new_port 已成功开放。${NC}"
  fi

  # 关闭旧端口（如果存在且不同于新端口）
  if [ -n "$old_port" ] && [ "$old_port" != "$new_port" ] && [ "$old_port" != "22" ]; then
    echo -e "${BLUE}正在关闭旧端口 $old_port...${NC}"
    if command -v ufw &>/dev/null; then
      ufw deny "$old_port/tcp"
    elif command -v firewall-cmd &>/dev/null; then
      firewall-cmd --permanent --remove-port="$old_port/tcp"
      firewall-cmd --reload
    elif command -v iptables &>/dev/null; then
      iptables -A INPUT -p tcp --dport "$old_port" -j DROP
      service iptables save
      service iptables restart
    fi
    echo -e "${GREEN}旧端口 $old_port 已关闭。${NC}"
  fi
}

# 检查SSH服务
check_ssh_service
echo

# 四、启用 BBR+FQ
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

# 五、清理系统垃圾
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

# 六、清理日志文件（用户选择清理时间范围）
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

# 七、系统优化完成提示
echo -e "${GREEN}系统优化完成！${NC}"
echo

echo -e "本次优化包括："
echo -e "1) ${GREEN}更新了系统并安装了常用组件（如 sudo, wget, curl, fail2ban, ufw）。${NC}"
echo -e "2) ${GREEN}检测并配置了IPv4/IPv6环境，确保网络访问正常。${NC}"
echo -e "3) ${GREEN}设置了SSH端口，增强了远程登录安全性。${NC}"
echo -e "4) ${GREEN}启用了防火墙并配置了常用端口，特别是 SSH 服务端口。${NC}"
echo -e "5) ${GREEN}启用了 Fail2Ban 防护，增强了系统安全性。${NC}"
echo -e "6) ${GREEN}根据您的选择，已调整系统时区设置。${NC}"
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
else
    echo -e "${GREEN}系统优化完成，无需重启。${NC}"
fi

echo -e "${GREEN}所有操作已完成，系统已经优化并增强了安全性！${NC}"
echo -e "${YELLOW}如果修改了SSH端口，记得在SSH工具上修改为新的端口，否则无法连接。${NC}"
