#!/bin/bash

# ANSI颜色码
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
        SYSTEM_CODENAME=$VERSION_CODENAME
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
        SYSTEM_NAME=$(dpkg --status lsb-release | grep "Package" | awk '{print $2}')
        SYSTEM_CODENAME=$(dpkg --status lsb-release | grep "Version" | awk '{print $2}')
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
    if [[ -z "$SYSTEM_NAME" || -z "$SYSTEM_CODENAME" || -z "$SYSTEM_VERSION" ]]; then
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

# 二、更新系统
echo -e "${BLUE}正在更新系统...${NC}"
echo
if command -v apt &> /dev/null; then
  apt update && apt upgrade -y
elif command -v yum &> /dev/null; then
  yum update -y
else
  echo -e "${RED}未检测到 apt 或 yum，无法更新系统${NC}"
  exit 1
fi

echo -e "${GREEN}系统更新完成。${NC}"
echo

# 一、检查并安装常用组件
echo -e "${BLUE}正在检查并安装常用组件：sudo, wget, curl, fail2ban, ufw...${NC}"
echo

# 检查并安装 sudo
if ! command -v sudo &> /dev/null; then
  echo -e "${YELLOW}未检测到 sudo，正在安装...${NC}"
  apt install -y sudo || yum install -y sudo
else
  echo -e "${GREEN}sud 已安装${NC}"
fi

# 检查并安装 wget
if ! command -v wget &> /dev/null; then
  echo -e "${YELLOW}未检测到 wget，正在安装...${NC}"
  apt install -y wget || yum install -y wget
else
  echo -e "${GREEN}wget 已安装${NC}"
fi

# 检查并安装 curl
if ! command -v curl &> /dev/null; then
  echo -e "${YELLOW}未检测到 curl，正在安装...${NC}"
  apt install -y curl || yum install -y curl
else
  echo -e "${GREEN}curl 已安装${NC}"
fi

# 检查并安装 fail2ban
if ! command -v fail2ban-client &> /dev/null; then
  echo -e "${YELLOW}未检测到 fail2ban，正在安装...${NC}"
  apt install -y fail2ban || yum install -y fail2ban
else
  echo -e "${GREEN}fail2ban 已安装${NC}"
fi

# 检查并安装 ufw
if ! command -v ufw &> /dev/null; then
  echo -e "${YELLOW}未检测到 ufw，正在安装...${NC}"
  apt install -y ufw || yum install -y ufw
else
  echo -e "${GREEN}ufw 已安装${NC}"
fi

echo -e "${GREEN}常用组件安装完成。${NC}"
echo

# 检测并设置网络优先级的功能模块
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

    # 检测当前优先级设置
    if sysctl net.ipv6.conf.all.prefer_ipv4 &>/dev/null; then
        ipv4_preference=$(sysctl net.ipv6.conf.all.prefer_ipv4 | awk '{print $3}')
        if [ "$ipv4_preference" == "1" ]; then
            current_preference="IPv4优先"
        elif [ "$ipv4_preference" == "0" ]; then
            if [ "$ipv4_valid" == false ] && [ "$ipv6_valid" == true ]; then
                echo -e "${YELLOW}检测到本机为IPv6 only网络环境。${NC}"
                current_preference="IPv6优先"
            else
                current_preference="IPv6优先"
            fi
        else
            current_preference="未配置"
        fi
        echo -e "当前系统的优先级设置是: ${GREEN}$current_preference${NC}"
    else
        if [ "$ipv4_valid" == false ] && [ "$ipv6_valid" == true ]; then
            echo -e "${YELLOW}检测到本机为IPv6 only网络环境。${NC}"
        fi
        echo -e "未找到 prefer_ipv4 配置项，默认未配置优先级"
    fi

    # 如果是双栈模式，提供选择优先级的选项
    if [ -n "$ipv4_address" ] && [ -n "$ipv6_address" ] && [ "$ipv6_valid" == true ] && [ "$ipv4_valid" == true ]; then
        echo -e "${BLUE}本机为双栈模式，您可以选择优先使用IPv4或IPv6。${NC}"
        echo -e "请选择优先使用的协议："
        select choice in "IPv4优先" "IPv6优先" "取消"; do
            case $choice in
                "IPv4优先")
                    echo -e "您选择了IPv4优先。"
                    # 设置IPv4优先并写入 /etc/sysctl.conf 使其永久生效
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=1
                    sudo sysctl -w net.ipv6.conf.default.prefer_ipv4=1
                    echo "net.ipv6.conf.all.prefer_ipv4=1" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "net.ipv6.conf.default.prefer_ipv4=1" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo -e "已设置IPv4优先，并且配置已永久生效。"
                    break
                    ;;
                "IPv6优先")
                    echo -e "您选择了IPv6优先。"
                    # 设置IPv6优先并写入 /etc/sysctl.conf 使其永久生效
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=0
                    sudo sysctl -w net.ipv6.conf.default.prefer_ipv4=0
                    echo "net.ipv6.conf.all.prefer_ipv4=0" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "net.ipv6.conf.default.prefer_ipv4=0" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo -e "已设置IPv6优先，并且配置已永久生效。"
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

# 后续大脚本的其他内容
echo -e "${GREEN}继续执行后续脚本...${NC}"
echo

# 检查SSH服务是否安装并运行
check_ssh_service() {
  echo -e "${BLUE}现在开始检测SSH端口...${NC}"
  echo

  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo -e "${YELLOW}未检测到SSH服务。${NC}"
    read -p "是否需要启动并设置SSH服务并更改端口号（y/n）？" choice
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

      echo -e "SSH 配置已更新，新的端口号为: ${GREEN}$new_port${NC}"
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
  check_firewall
}

# 检查防火墙并开放新端口
check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    # ufw防火墙启用检查
    if ! sudo ufw status | grep -q "Status: active"; then
      echo -e "${YELLOW}防火墙未启用，且新端口未被防火墙阻拦。${NC}"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! sudo ufw status | grep -q "$new_port/tcp"; then
        sudo ufw allow $new_port/tcp
        echo -e "${GREEN}防火墙已启用，新端口已添加放行规则。${NC}"
      else
        echo -e "${GREEN}新端口已开放，防火墙规则已放行该端口。${NC}"
      fi
    fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # firewalld防火墙启用检查
    if ! sudo systemctl is-active --quiet firewalld; then
      echo -e "${YELLOW}防火墙未启用，且新端口未被防火墙阻拦。${NC}"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! sudo firewall-cmd --list-all | grep -q "$new_port/tcp"; then
        sudo firewall-cmd --permanent --add-port=$new_port/tcp
        sudo firewall-cmd --reload
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
  if ! ss -tuln | grep -q $new_port; then
    echo -e "${RED}错误：新端口 $new_port 未成功开放，执行修复步骤...${NC}"
    
    # 执行修复步骤：重新加载配置并重启SSH服务
    echo -e "执行 ${GREEN}systemctl daemon-reload${NC}"
    sudo systemctl daemon-reload

    echo -e "执行 ${GREEN}/etc/init.d/ssh restart${NC}"
    sudo /etc/init.d/ssh restart

    echo -e "执行 ${GREEN}systemctl restart ssh${NC}"
    sudo systemctl restart ssh

    # 再次检查新端口是否生效
    echo -e "检查新端口是否生效..."
    ss -tuln | grep $new_port

    # 即使修复失败，也只提示，不退出，跳过当前功能块
    if ! ss -tuln | grep -q $new_port; then
      echo -e "${YELLOW}警告：修复后新端口 $new_port 仍未成功开放，跳过该功能块，继续后续任务。${NC}"
    fi
  else
    echo -e "${GREEN}新端口 $new_port 已成功开放。${NC}"
  fi
}

# 安装并启动SSH服务
install_ssh() {
  if [[ "$os_type" == "ubuntu" || "$os_type" == "debian" ]]; then
    # Ubuntu/Debian 系统
    if ! systemctl is-active --quiet ssh; then
      echo -e "${YELLOW}SSH 服务未安装或未启动，正在安装 SSH 服务...${NC}"
      apt update && apt install -y openssh-server
      systemctl enable ssh
      systemctl start ssh
      echo -e "${GREEN}SSH 服务已安装并启动！${NC}"
    fi
  elif [[ "$os_type" == "centos" || "$os_type" == "rhel" ]]; then
    # CentOS/RHEL 系统
    if ! systemctl is-active --quiet sshd; then
      echo -e "${YELLOW}SSH 服务未安装或未启动，正在安装 SSH 服务...${NC}"
      yum install -y openssh-server
      systemctl enable sshd
      systemctl start sshd
      echo -e "${GREEN}SSH 服务已安装并启动！${NC}"
    fi
  else
    echo -e "${RED}无法识别的操作系统：$os_type，无法处理 SSH 服务。${NC}"
    return  # 跳过当前功能块，继续执行后续部分
  fi
}

# 调用检查SSH服务函数
check_ssh_service
echo

# 检测 SSH 服务是否启用的方法
echo -e "${BLUE}正在检测 SSH 服务状态...${NC}"
echo

# 使用 systemctl 检测 SSH 服务
if systemctl is-active --quiet sshd; then
  ssh_status="enabled"
else
  # 如果 systemctl 检测失败，检查 sshd 进程是否存在
  if pgrep -x "sshd" > /dev/null; then
    ssh_status="enabled (via process)"
  else
    ssh_status="disabled"
  fi
fi

if [ "$ssh_status" == "disabled" ]; then
  echo -e "${YELLOW}当前未启用 SSH 服务，跳过检查端口的步骤。${NC}"
  echo -e "${RED}注意：如果继续执行脚本，可能会导致所有 SSH 端口关闭，进而无法通过 SSH 登录系统。${NC}"
  read -p "您确定要继续吗？（继续请输入 y，取消请输入 n）： " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo -e "${RED}脚本执行已取消。${NC}"
    exit 1
  fi
else
  # 检测当前所有的 SSH 服务端口
  echo -e "${BLUE}正在检测当前 SSH 服务端口...${NC}"
  echo

  # 尝试从 SSH 配置文件中获取端口，忽略带注释的行
  ssh_config_file="/etc/ssh/sshd_config"
  if [ ! -f "$ssh_config_file" ]; then
    echo -e "${RED}错误：找不到 SSH 配置文件 $ssh_config_file${NC}"
    exit 1
  fi

  # 提取配置文件中的所有不带注释的 Port 设置，去除注释和空行
  ssh_ports=$(grep -E "^\s*Port\s+" "$ssh_config_file" | grep -v '^#' | awk '{print $2}' | sort | uniq)

  # 如果配置文件中没有找到端口，则默认使用 22
  if [ -z "$ssh_ports" ]; then
    echo -e "${YELLOW}未在 SSH 配置文件中找到端口设置，默认端口为 22。${NC}"
    read -p "是否继续执行脚本？（继续请输入 y，取消请输入 n）： " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
      echo -e "${RED}脚本执行已取消。${NC}"
      exit 1
    fi
    ssh_ports="22"
  else
    echo -e "检测到以下 SSH 端口（不带注释的）："
    i=1
    for port in $ssh_ports; do
      echo -e "$i) $port"
      ((i++))
    done

    # 提示用户选择要保留的端口
    read -p "请输入端口号的序号（例如 1, 2, 3...）： " selected_option

    # 获取选择的端口
    selected_port=$(echo "$ssh_ports" | sed -n "${selected_option}p")

    # 检查输入的端口是否有效
    if [ -z "$selected_port" ]; then
      echo -e "${RED}错误：所选端口无效，脚本退出。${NC}"
      exit 1
    fi

    echo -e "您选择保留的 SSH 端口为: ${GREEN}$selected_port${NC}"
    
    # 关闭其他 SSH 端口
    i=1
    for port in $ssh_ports; do
      if [ "$port" != "$selected_port" ]; then
        echo -e "正在关闭 SSH 端口 $port..."
        ufw deny $port/tcp
      fi
      ((i++))
    done
  fi
fi

# 四、启用防火墙（UFW 或 firewalld）
echo -e "${BLUE}正在检查并启用防火墙...${NC}"
echo

# 检查是否安装了ufw
if ! command -v ufw &>/dev/null; then
  echo -e "${YELLOW}未检测到 ufw，正在安装 ufw...${NC}"
  if command -v apt &>/dev/null; then
    # Ubuntu 或 Debian 系统
    sudo apt update
    sudo apt install -y ufw
  elif command -v yum &>/dev/null; then
    # CentOS 或 RHEL 系统
    sudo yum install -y ufw
  fi
fi

# 确保ufw防火墙启用
if ! sudo ufw status &>/dev/null; then
  echo -e "${YELLOW}正在启用 ufw 防火墙...${NC}"
  sudo ufw enable
fi

# 开放指定端口
sudo ufw allow ssh
echo -e "${GREEN}SSH 端口已开放。${NC}"

# 开放新端口
sudo ufw allow $new_port/tcp
echo -e "新端口 $new_port 已开放。"

# 关闭旧端口
sudo ufw delete allow $current_port/tcp || echo -e "${YELLOW}警告：未找到旧端口 $current_port 的规则${NC}"
echo -e "旧端口 $current_port 已关闭。"

# 重新加载防火墙规则
sudo ufw reload
echo -e "${GREEN}防火墙规则已重新加载。${NC}"

# 开放所选的 SSH 端口
if [ "$ssh_ports" != "22" ]; then
  echo -e "${BLUE}正在开放所选的 SSH 端口 $selected_port...${NC}"
  ufw allow $selected_port/tcp
else
  echo -e "${GREEN}默认端口 22 已开放${NC}"
fi

# 检测其他常用服务的端口并开放
echo -e "${BLUE}正在检测并开放常用服务端口...${NC}"
echo

# 使用 ss 或 netstat 检测所有监听的端口
ss -tuln | grep -E "tcp|udp" | awk '{print $5}' | cut -d: -f2 | sort | uniq | while read port; do
  # 跳过端口为空或不存在的情况
  if [ -z "$port" ]; then
    continue
  fi

  # 检查是否已经开放此端口
  if ! sudo ufw status | grep -q "$port"; then
    echo -e "正在开放端口 $port..."
    sudo ufw allow $port/tcp   # 开放 TCP 协议的端口
    sudo ufw allow $port/udp   # 开放 UDP 协议的端口
  fi
done

# 重新加载防火墙规则，确保更改生效
sudo ufw reload
echo -e "${GREEN}所有占用端口已成功开放。${NC}"

echo -e "${GREEN}所有已使用的端口已开放。${NC}"
echo

# 启用 Fail2Ban
echo -e "${BLUE}正在启用 Fail2Ban...${NC}"
systemctl enable fail2ban
systemctl start fail2ban
echo -e "${GREEN}Fail2Ban 启用成功。${NC}"

# 确保防火墙规则生效
ufw reload
echo -e "${GREEN}防火墙规则已重新加载。${NC}"

# 完成提示
echo -e "${GREEN}脚本执行完成！${NC}"
echo

# 输出当前服务的防火墙状态
echo -e "${BLUE}当前服务的防火墙状态：${NC}"
ufw status verbose
echo

# 检查 Fail2Ban 状态
echo -e "${BLUE}Fail2Ban 状态：${NC}"
fail2ban-client status
echo

# 显示当前时区
echo -e "${BLUE}当前时区是：$(timedatectl show --property=Timezone --value)${NC}"
echo

# 显示时区选择菜单
echo -e "${BLUE}请选择要设置的时区：${NC}"
echo "1) 上海 (东八区, UTC+8)"
echo "2) 纽约 (美国东部时区, UTC-5)"
echo "3) 洛杉矶 (美国西部时区, UTC-8)"
echo "4) 伦敦 (零时区, UTC+0)"
echo "5) 东京 (东九区, UTC+9)"
echo "6) 巴黎 (欧洲中部时区, UTC+1)"
echo "7) 曼谷 (东七区, UTC+7)"
echo "8) 悉尼 (东十区, UTC+10)"
echo "9) 迪拜 (海湾标准时区, UTC+4)"
echo "10) 里约热内卢 (巴西时间, UTC-3)"
echo "11) 维持当前时区"

# 获取用户输入
read -p "请输入选项 (1/2/3/4/5/6/7/8/9/10/11): " timezone_choice

# 根据用户选择设置时区
case $timezone_choice in
  1)
    echo -e "${BLUE}正在设置时区为 上海 (东八区, UTC+8)...${NC}"
    sudo timedatectl set-timezone Asia/Shanghai
    ;;
  2)
    echo -e "${BLUE}正在设置时区为 纽约 (美国东部时区, UTC-5)...${NC}"
    sudo timedatectl set-timezone America/New_York
    ;;
  3)
    echo -e "${BLUE}正在设置时区为 洛杉矶 (美国西部时区, UTC-8)...${NC}"
    sudo timedatectl set-timezone America/Los_Angeles
    ;;
  4)
    echo -e "${BLUE}正在设置时区为 伦敦 (零时区, UTC+0)...${NC}"
    sudo timedatectl set-timezone Europe/London
    ;;
  5)
    echo -e "${BLUE}正在设置时区为 东京 (东九区, UTC+9)...${NC}"
    sudo timedatectl set-timezone Asia/Tokyo
    ;;
  6)
    echo -e "${BLUE}正在设置时区为 巴黎 (欧洲中部时区, UTC+1)...${NC}"
    sudo timedatectl set-timezone Europe/Paris
    ;;
  7)
    echo -e "${BLUE}正在设置时区为 曼谷 (东七区, UTC+7)...${NC}"
    sudo timedatectl set-timezone Asia/Bangkok
    ;;
  8)
    echo -e "${BLUE}正在设置时区为 悉尼 (东十区, UTC+10)...${NC}"
    sudo timedatectl set-timezone Australia/Sydney
    ;;
  9)
    echo -e "${BLUE}正在设置时区为 迪拜 (海湾标准时区, UTC+4)...${NC}"
    sudo timedatectl set-timezone Asia/Dubai
    ;;
  10)
    echo -e "${BLUE}正在设置时区为 里约热内卢 (巴西时间, UTC-3)...${NC}"
    sudo timedatectl set-timezone America/Sao_Paulo
    ;;
  11)
    echo -e "${YELLOW}您选择维持当前时区，脚本将继续执行。${NC}"
    ;;
  *)
    echo -e "${YELLOW}无效选项，选择维持当前时区。${NC}"
    ;;
esac

# 提示用户时区已设置完成
echo -e "${GREEN}时区设置完成！${NC}"
echo

# 检测当前的 SWAP 配置
echo -e "${BLUE}正在检测当前的内存和 SWAP 配置...${NC}"
echo

# 使用 swapon -s 方法检查
swap_info=$(swapon -s)

# 使用 free 命令检查
free_info=$(free -h | grep -i swap)

# 如果 SWAP 已配置，则显示当前 SWAP 配置
if [ -n "$swap_info" ] || [ -n "$free_info" ]; then
  echo -e "${BLUE}当前内存和 SWAP 配置：${NC}"
  free -h
else
  # 如果没有配置 SWAP，则显示无 SWAP
  echo -e "${YELLOW}当前没有配置 SWAP 分区。${NC}"
  free -h
fi

# 提示用户选择操作：增加、减少、或者不调整 SWAP
echo -e "${BLUE}请选择操作：${NC}"
echo "1) 增加 SWAP"
echo "2) 减少 SWAP"
echo "3) 不调整 SWAP"
read -p "请输入选项 (1/2/3): " swap_choice

case $swap_choice in
  1)
    # 增加 SWAP
    read -p "请输入增加的 SWAP 大小 (单位 MB): " swap_add_size
    echo -e "${BLUE}正在增加 $swap_add_size MB 的 SWAP...${NC}"
    
    # 创建 SWAP 文件
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$swap_add_size
    sudo chmod 600 /swapfile
    
    # 格式化 SWAP 文件
    sudo mkswap /swapfile
    
    # 启用 SWAP 文件
    sudo swapon /swapfile
    
    # 将 SWAP 文件添加到 /etc/fstab，确保重启后生效
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
    fi
    
    echo -e "${GREEN}已成功增加 $swap_add_size MB 的 SWAP。${NC}"
    ;;
  2)
    # 减少 SWAP
    echo -e "${BLUE}正在减少 SWAP...${NC}"
    
    # 禁用 SWAP 文件
    if swapon -s | grep -q "/swapfile"; then
        sudo swapoff /swapfile
    fi
    
    # 删除 SWAP 文件
    if [ -f "/swapfile" ]; then
        sudo rm /swapfile
    fi
    
    # 从 /etc/fstab 中移除 SWAP 配置
    if grep -q "/swapfile" /etc/fstab; then
        sudo sed -i '/\/swapfile/d' /etc/fstab
    fi
    
    echo -e "${GREEN}已成功减少 SWAP。${NC}"
    ;;
  3)
    # 不调整 SWAP
    echo -e "${YELLOW}您选择不调整 SWAP。${NC}"
    ;;
  *)
    echo -e "${YELLOW}无效选项，退出程序。${NC}"
    ;;
esac

# 提示当前的内存和 SWAP 信息
echo -e "${BLUE}当前的内存和 SWAP 配置：${NC}"
free -h
echo

# 提示按 Enter 键继续
read -p "已显示当前的内存和 SWAP 配置，按 Enter 键继续..."

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

# 启用 BBR+FQ
enable_bbr_fq() {
    echo -e "${BLUE}正在启用 BBR 和 BBR+FQ 加速方案...${NC}"

    # 启用 BBR
    sudo sysctl -w net.ipv4.tcp_congestion_control=bbr

    # 永久启用 BBR（在 /etc/sysctl.conf 中添加配置）
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    fi

    # 启用 FQ（FQ是BBR的配套方案）
    sudo sysctl -w net.ipv4.tcp_default_congestion_control=bbr
    sudo sysctl -w net.core.default_qdisc=fq

    # 永久启用 FQ
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    fi

    # 重新加载 sysctl 配置
    sudo sysctl -p

    echo -e "${GREEN}BBR 和 BBR+FQ 已成功启用！${NC}"
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

# 四、清理系统垃圾
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
rm -rf /tmp/*
rm -rf /var/tmp/*

echo -e "${GREEN}系统垃圾清理完成！${NC}"
echo

# 五、清理日志文件（用户选择清理时间范围）
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

# 六、系统优化完成提示
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
        sudo reboot
    else
        echo -e "${YELLOW}您选择稍后手动重启系统。${NC}"
    fi
else
    echo -e "${GREEN}系统优化完成，无需重启。${NC}"
fi

echo -e "${GREEN}所有操作已完成，系统已经优化并增强了安全性！${NC}"
echo -e "${YELLOW}如果修改了SSH端口，记得在SSH工具上修改为新的端口，否则无法连接${NC}"
