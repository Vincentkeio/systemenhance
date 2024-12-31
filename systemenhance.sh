#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用root权限运行此脚本！"
  exit 1
fi

# 提示用户开始操作
echo "开始执行系统优化脚本..."
#显示系统信息
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
        echo "无法获取系统信息"
        fi
}

# 获取系统信息
get_system_info

# 显示系统详细信息
echo "操作系统: $SYSTEM_NAME"
echo "版本号: $SYSTEM_VERSION"
echo "代号: $SYSTEM_CODENAME"
echo "内核版本: $KERNEL_VERSION"
echo "系统架构: $SYSTEM_ARCH"

# 二、更新系统
echo "正在更新系统..."
if command -v apt &> /dev/null; then
  apt update && apt upgrade -y
elif command -v yum &> /dev/null; then
  yum update -y
else
  echo "未检测到 apt 或 yum，无法更新系统"
  exit 1
fi

echo "系统更新完成。"

# 一、检查并安装常用组件
echo "正在检查并安装常用组件：sudo, wget, curl, fail2ban, ufw..."

# 检查并安装 sudo
if ! command -v sudo &> /dev/null; then
  echo "未检测到 sudo，正在安装..."
  apt install -y sudo || yum install -y sudo
else
  echo "sudo 已安装"
fi

# 检查并安装 wget
if ! command -v wget &> /dev/null; then
  echo "未检测到 wget，正在安装..."
  apt install -y wget || yum install -y wget
else
  echo "wget 已安装"
fi

# 检查并安装 curl
if ! command -v curl &> /dev/null; then
  echo "未检测到 curl，正在安装..."
  apt install -y curl || yum install -y curl
else
  echo "curl 已安装"
fi

# 检查并安装 fail2ban
if ! command -v fail2ban-client &> /dev/null; then
  echo "未检测到 fail2ban，正在安装..."
  apt install -y fail2ban || yum install -y fail2ban
else
  echo "fail2ban 已安装"
fi

# 检查并安装 ufw
if ! command -v ufw &> /dev/null; then
  echo "未检测到 ufw，正在安装..."
  apt install -y ufw || yum install -y ufw
else
  echo "ufw 已安装"
fi

echo "常用组件安装完成。"

#IPV4/IPV6网络设置

#!/bin/bash

# 检测并设置网络优先级的功能模块
check_and_set_network_priority() {
    # 输出开始信息
    echo "现在开始IPv4/IPv6网络配置"

    # 检测本机的IPv4和IPv6地址
    ipv4_address=$(hostname -I | awk '{print $1}')
    ipv6_address=$(hostname -I | awk '{print $2}')

    # 显示IPv4和IPv6地址，或提示没有该地址
    if [ -z "$ipv4_address" ]; then
        echo "本机无IPv4地址"
    else
        echo "本机IPv4地址: $ipv4_address"
    fi

    if [ -z "$ipv6_address" ]; then
        echo "本机无IPv6地址"
    else
        echo "本机IPv6地址: $ipv6_address"
    fi

    # 检测当前优先级设置
    ipv4_preference=$(sysctl net.ipv6.conf.all.prefer_ipv4 | awk '{print $3}')
    if [ "$ipv4_preference" == "1" ]; then
        current_preference="IPv4优先"
    elif [ "$ipv4_preference" == "0" ]; then
        current_preference="IPv6优先"
    else
        current_preference="未配置"
    fi
    echo "当前系统的优先级设置是: $current_preference"

    # 如果是双栈模式，提供选择优先级的选项
    if [ -n "$ipv4_address" ] && [ -n "$ipv6_address" ]; then
        echo "本机为双栈模式，您可以选择优先使用IPv4或IPv6。"
        echo "请选择优先使用的协议："
        select choice in "IPv4优先" "IPv6优先" "取消"; do
            case $choice in
                "IPv4优先")
                    echo "您选择了IPv4优先。"
                    # 设置IPv4优先并写入 /etc/sysctl.conf 使其永久生效
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=1
                    sudo sysctl -w net.ipv6.conf.default.prefer_ipv4=1
                    echo "net.ipv6.conf.all.prefer_ipv4=1" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "net.ipv6.conf.default.prefer_ipv4=1" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "已设置IPv4优先，并且配置已永久生效。"
                    break
                    ;;
                "IPv6优先")
                    echo "您选择了IPv6优先。"
                    # 设置IPv6优先并写入 /etc/sysctl.conf 使其永久生效
                    sudo sysctl -w net.ipv6.conf.all.prefer_ipv4=0
                    sudo sysctl -w net.ipv6.conf.default.prefer_ipv4=0
                    echo "net.ipv6.conf.all.prefer_ipv4=0" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "net.ipv6.conf.default.prefer_ipv4=0" | sudo tee -a /etc/sysctl.conf > /dev/null
                    echo "已设置IPv6优先，并且配置已永久生效。"
                    break
                    ;;
                "取消")
                    echo "您选择了取消。"
                    break
                    ;;
                *)
                    echo "无效选择，请重新选择。"
                    ;;
            esac
        done
    else
        # 如果本机不是双栈，提示是否安装WARP
        echo "您的本机不是双栈模式（没有IPv4和IPv6同时存在）。"
        echo "您可以选择安装WARP来实现双栈访问外部网站。"
        read -p "是否安装WARP？（y/n）" warp_choice
        case $warp_choice in
            [Yy]*)
                echo "正在安装WARP..."

                # 安装依赖项
                sudo apt update
                sudo apt install -y wireguard curl

                # 下载并安装 WARP
                curl -fsSL https://warp.cloudflare.com | sudo bash

                # 启动 WARP
                echo "WARP安装完成，正在启动..."
                sudo systemctl enable wg-quick@wg0
                sudo systemctl start wg-quick@wg0

                # 检查 WARP 状态
                sudo systemctl status wg-quick@wg0

                # 检查连接
                if sudo wg show wg0; then
                    echo "WARP 已成功连接，您现在可以通过双栈访问外部网站。"
                else
                    echo "WARP 连接失败，请检查网络配置。"
                fi
                ;;
            [Nn]*)
                echo "您选择了不安装WARP。"
                ;;
            *)
                echo "无效选择。"
                ;;
        esac
    fi
}

# 启用WARP时，提供选择是启用双栈均通过WARP访问，还是仅启用缺失部分
enable_warp_for_dual_stack() {
    echo "现在开始配置 WARP 的使用方式"

    # 判断本机的IPv4和IPv6情况
    if [ -n "$ipv4_address" ] && [ -n "$ipv6_address" ]; then
        echo "您的本机支持IPv4和IPv6地址。"
        echo "请选择 WARP 配置方式："
        select warp_choice in "双栈均使用WARP" "仅在缺失部分使用WARP" "取消"; do
            case $warp_choice in
                "双栈均使用WARP")
                    echo "您选择了双栈均使用WARP。"
                    # 启用WARP并配置双栈使用
                    sudo wg-quick up wg0
                    echo "双栈均已启用WARP访问外网。"
                    break
                    ;;
                "仅在缺失部分使用WARP")
                    echo "您选择了仅在缺失部分使用WARP。"

                    # 检查本机是否已启用IPv4或IPv6
                    if [ -z "$ipv4_address" ]; then
                        echo "本机缺少IPv4地址，使用WARP进行IPv4访问..."
                        sudo wg-quick up wg0
                    fi

                    if [ -z "$ipv6_address" ]; then
                        echo "本机缺少IPv6地址，使用WARP进行IPv6访问..."
                        sudo wg-quick up wg0
                    fi
                    break
                    ;;
                "取消")
                    echo "您选择了取消。"
                    break
                    ;;
                *)
                    echo "无效选择，请重新选择。"
                    ;;
            esac
        done
    else
        echo "您的本机不支持双栈，WARP将仅启用在缺少的部分。"
        sudo wg-quick up wg0
    fi
}

# 调用功能模块并捕获错误
{
    check_and_set_network_priority
    enable_warp_for_dual_stack
} || {
    echo "网络配置模块发生错误，但不会中断后续脚本执行。"
}

# 后续大脚本的其他内容
echo "继续执行后续脚本..."
# 这里可以继续编写大脚本的其他部分



#SSH端口功能

# 检查SSH服务是否安装并运行
check_ssh_service() {
  echo "现在开始检测SSH端口..."

  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo "未检测到SSH服务。"
    read -p "是否需要启动并设置SSH服务并更改端口号（y/n）？" choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
      install_ssh
      configure_ssh_port
    else
      echo "跳过SSH服务设置，继续执行其他任务。"
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

  echo "当前SSH端口为: $current_port"

  # 询问用户是否需要修改SSH端口
  read -p "是否需要修改SSH端口？(y/n): " modify_choice
  if [[ "$modify_choice" == "y" || "$modify_choice" == "Y" ]]; then
    # 提示用户输入新的SSH端口
    read -p "请输入新的SSH端口号 (1-65535): " new_port

    # 验证端口号是否有效
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
      echo "错误：请输入一个有效的端口号（1-65535）！"
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

      echo "SSH 配置已更新，新的端口号为: $new_port"
    else
      echo "错误：找不到SSH配置文件 $ssh_config_file"
      return  # 跳过当前功能块，继续执行后续部分
    fi

    # 检查修改后的配置是否生效
    current_port_in_ssh_config=$(grep "^Port " "$ssh_config_file" | awk '{print $2}')
    
    if [ "$current_port_in_ssh_config" -eq "$new_port" ]; then
      echo "SSH端口修改成功，新端口为 $new_port"
    else
      echo "错误：SSH端口修改失败，请检查配置。"
      return  # 跳过当前功能块，继续执行后续部分
    fi
  else
    echo "跳过SSH端口修改，继续执行其他任务。"
  fi

  # 检查SSH服务是否已正常启用
  if ! systemctl is-active --quiet ssh && ! systemctl is-active --quiet sshd; then
    echo "警告：SSH服务未正常启用，无法继续检查新端口是否生效。"
    return  # 跳过当前功能块，继续执行后续部分
  else
    echo "SSH服务已正常启用，继续检查新端口是否生效。"
  fi

  # 检查新端口是否在防火墙中开放
  check_firewall
}

# 检查防火墙并开放新端口
check_firewall() {
  if command -v ufw >/dev/null 2>&1; then
    # ufw防火墙启用检查
    if ! sudo ufw status | grep -q "Status: active"; then
      echo "防火墙未启用，且新端口未被防火墙阻拦。"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! sudo ufw status | grep -q "$new_port/tcp"; then
        sudo ufw allow $new_port/tcp
        echo "防火墙已启用，新端口已添加放行规则。"
      else
        echo "新端口已开放，防火墙规则已放行该端口。"
      fi
    fi
  elif command -v firewall-cmd >/dev/null 2>&1; then
    # firewalld防火墙启用检查
    if ! sudo systemctl is-active --quiet firewalld; then
      echo "防火墙未启用，且新端口未被防火墙阻拦。"
    else
      # 检查新端口是否已在防火墙规则中放行
      if ! sudo firewall-cmd --list-all | grep -q "$new_port/tcp"; then
        sudo firewall-cmd --permanent --add-port=$new_port/tcp
        sudo firewall-cmd --reload
        echo "防火墙已启用，新端口已添加放行规则。"
      else
        echo "新端口已开放，防火墙规则已放行该端口。"
      fi
    fi
  else
    echo "警告：未检测到受支持的防火墙工具，请手动开放新端口 $new_port。"
    echo "防火墙未启用，且新端口未被防火墙阻拦。"
  fi

  # 检查新端口是否成功开放
  if ! ss -tuln | grep -q $new_port; then
    echo "错误：新端口 $new_port 未成功开放，执行修复步骤..."
    
    # 执行修复步骤：重新加载配置并重启SSH服务
    echo "执行 systemctl daemon-reload..."
    sudo systemctl daemon-reload

    echo "执行 /etc/init.d/ssh restart..."
    sudo /etc/init.d/ssh restart

    echo "执行 systemctl restart ssh..."
    sudo systemctl restart ssh

    # 再次检查新端口是否生效
    echo "检查新端口是否生效..."
    ss -tuln | grep $new_port

    # 即使修复失败，也只提示，不退出，跳过当前功能块
    if ! ss -tuln | grep -q $new_port; then
      echo "警告：修复后新端口 $new_port 仍未成功开放，跳过该功能块，继续后续任务。"
    fi
  else
    echo "新端口 $new_port 已成功开放。"
  fi
}

# 安装并启动SSH服务
install_ssh() {
  if [[ "$os_type" == "ubuntu" || "$os_type" == "debian" ]]; then
    # Ubuntu/Debian 系统
    if ! systemctl is-active --quiet ssh; then
      echo "SSH 服务未安装或未启动，正在安装 SSH 服务..."
      apt update && apt install -y openssh-server
      systemctl enable ssh
      systemctl start ssh
      echo "SSH 服务已安装并启动！"
    fi
  elif [[ "$os_type" == "centos" || "$os_type" == "rhel" ]]; then
    # CentOS/RHEL 系统
    if ! systemctl is-active --quiet sshd; then
      echo "SSH 服务未安装或未启动，正在安装 SSH 服务..."
      yum install -y openssh-server
      systemctl enable sshd
      systemctl start sshd
      echo "SSH 服务已安装并启动！"
    fi
  else
    echo "无法识别的操作系统：$os_type，无法处理 SSH 服务。"
    return  # 跳过当前功能块，继续执行后续部分
  fi
}

# 调用检查SSH服务函数
check_ssh_service


# 三、启用防火墙和 fail2ban

# 检测 SSH 服务是否启用的方法
echo "正在检测 SSH 服务状态..."

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
  echo "当前未启用 SSH 服务，跳过检查端口的步骤。"
  echo "注意：如果继续执行脚本，可能会导致所有 SSH 端口关闭，进而无法通过 SSH 登录系统。"
  read -p "您确定要继续吗？（继续请输入 y，取消请输入 n）： " choice
  if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
    echo "脚本执行已取消。"
    exit 1
  fi
else
  # 检测当前所有的 SSH 服务端口
  echo "正在检测当前 SSH 服务端口..."

  # 尝试从 SSH 配置文件中获取端口，忽略带注释的行
  ssh_config_file="/etc/ssh/sshd_config"
  if [ ! -f "$ssh_config_file" ]; then
    echo "错误：找不到 SSH 配置文件 $ssh_config_file"
    exit 1
  fi

  # 提取配置文件中的所有不带注释的 Port 设置，去除注释和空行
  ssh_ports=$(grep -E "^\s*Port\s+" "$ssh_config_file" | grep -v '^#' | awk '{print $2}' | sort | uniq)

  # 如果配置文件中没有找到端口，则默认使用 22
  if [ -z "$ssh_ports" ]; then
    echo "未在 SSH 配置文件中找到端口设置，默认端口为 22。"
    read -p "是否继续执行脚本？（继续请输入 y，取消请输入 n）： " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
      echo "脚本执行已取消。"
      exit 1
    fi
    ssh_ports="22"
  else
    echo "检测到以下 SSH 端口（不带注释的）："
    i=1
    for port in $ssh_ports; do
      echo "$i) $port"
      ((i++))
    done

    # 提示用户选择要保留的端口
    read -p "请输入端口号的序号（例如 1, 2, 3...）： " selected_option

    # 获取选择的端口
    selected_port=$(echo "$ssh_ports" | sed -n "${selected_option}p")

    # 检查输入的端口是否有效
    if [ -z "$selected_port" ]; then
      echo "错误：所选端口无效，脚本退出。"
      exit 1
    fi

    echo "您选择保留的 SSH 端口为: $selected_port"
    
    # 关闭其他 SSH 端口
    i=1
    for port in $ssh_ports; do
      if [ "$port" != "$selected_port" ]; then
        echo "正在关闭 SSH 端口 $port..."
        ufw deny $port/tcp
      fi
      ((i++))
    done
  fi
fi

# 四、启用防火墙（UFW 或 firewalld）
echo "正在检查并启用防火墙..."

# 检查是否安装了ufw
if ! command -v ufw &>/dev/null; then
  echo "未检测到 ufw，正在安装 ufw..."
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
  echo "正在启用 ufw 防火墙..."
  sudo ufw enable
fi

# 开放指定端口
sudo ufw allow ssh
echo "SSH 端口已开放。"

# 开放新端口
sudo ufw allow $new_port/tcp
echo "新端口 $new_port 已开放。"

# 关闭旧端口
sudo ufw delete allow $current_port/tcp || echo "警告：未找到旧端口 $current_port 的规则"
echo "旧端口 $current_port 已关闭。"

# 重新加载防火墙规则
sudo ufw reload
echo "防火墙规则已重新加载。"


# 开放所选的 SSH 端口
if [ "$ssh_ports" != "22" ]; then
  echo "正在开放所选的 SSH 端口 $selected_port..."
  ufw allow $selected_port/tcp
else
  echo "默认端口 22 已开放"
fi

# 检测其他常用服务的端口并开放
echo "正在检测并开放常用服务端口..."

# 使用 ss 或 netstat 检测所有监听的端口
ss -tuln | grep -E "tcp|udp" | awk '{print $5}' | cut -d: -f2 | sort | uniq | while read port; do
  # 跳过端口为空或不存在的情况
  if [ -z "$port" ]; then
    continue
  fi

  # 检查是否已经开放此端口
  if ! sudo ufw status | grep -q "$port"; then
    echo "正在开放端口 $port..."
    sudo ufw allow $port/tcp   # 开放 TCP 协议的端口
    sudo ufw allow $port/udp   # 开放 UDP 协议的端口
  fi
done

# 重新加载防火墙规则，确保更改生效
sudo ufw reload
echo "所有占用端口已成功开放。"


echo "所有已使用的端口已开放。"

# 启用 Fail2Ban
echo "正在启用 Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban
echo "Fail2Ban 启用成功。"

# 确保防火墙规则生效
ufw reload
echo "防火墙规则已重新加载。"

# 完成提示
echo "脚本执行完成！"

# 输出当前服务的防火墙状态
ufw status verbose

# 检查 Fail2Ban 状态
fail2ban-client status

# 显示当前时区
echo "当前时区是：$(timedatectl show --property=Timezone --value)"

# 显示时区选择菜单
echo "请选择要设置的时区："
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
    echo "正在设置时区为 上海 (东八区, UTC+8)..."
    sudo timedatectl set-timezone Asia/Shanghai
    ;;
  2)
    echo "正在设置时区为 纽约 (美国东部时区, UTC-5)..."
    sudo timedatectl set-timezone America/New_York
    ;;
  3)
    echo "正在设置时区为 洛杉矶 (美国西部时区, UTC-8)..."
    sudo timedatectl set-timezone America/Los_Angeles
    ;;
  4)
    echo "正在设置时区为 伦敦 (零时区, UTC+0)..."
    sudo timedatectl set-timezone Europe/London
    ;;
  5)
    echo "正在设置时区为 东京 (东九区, UTC+9)..."
    sudo timedatectl set-timezone Asia/Tokyo
    ;;
  6)
    echo "正在设置时区为 巴黎 (欧洲中部时区, UTC+1)..."
    sudo timedatectl set-timezone Europe/Paris
    ;;
  7)
    echo "正在设置时区为 曼谷 (东七区, UTC+7)..."
    sudo timedatectl set-timezone Asia/Bangkok
    ;;
  8)
    echo "正在设置时区为 悉尼 (东十区, UTC+10)..."
    sudo timedatectl set-timezone Australia/Sydney
    ;;
  9)
    echo "正在设置时区为 迪拜 (海湾标准时区, UTC+4)..."
    sudo timedatectl set-timezone Asia/Dubai
    ;;
  10)
    echo "正在设置时区为 里约热内卢 (巴西时间, UTC-3)..."
    sudo timedatectl set-timezone America/Sao_Paulo
    ;;
  11)
    echo "您选择维持当前时区，脚本将继续执行。"
    ;;
  *)
    echo "无效选项，选择维持当前时区。"
    ;;
esac

# 提示用户时区已设置完成
echo "时区设置完成！"


# 检测当前的 SWAP 配置
echo "正在检测当前的内存和 SWAP 配置..."

# 使用 swapon -s 方法检查
swap_info=$(swapon -s)

# 使用 free 命令检查
free_info=$(free -h | grep -i swap)

# 如果 SWAP 已配置，则显示当前 SWAP 配置
if [ -n "$swap_info" ] || [ -n "$free_info" ]; then
  echo "当前内存和 SWAP 配置："
  free -h
else
  # 如果没有配置 SWAP，则显示无 SWAP
  echo "当前没有配置 SWAP 分区。"
  free -h
fi

# 提示用户选择操作：增加、减少、或者不调整 SWAP
echo "请选择操作："
echo "1) 增加 SWAP"
echo "2) 减少 SWAP"
echo "3) 不调整 SWAP"
read -p "请输入选项 (1/2/3): " swap_choice

case $swap_choice in
  1)
    # 增加 SWAP
    read -p "请输入增加的 SWAP 大小 (单位 MB): " swap_add_size
    echo "正在增加 $swap_add_size MB 的 SWAP..."
    # 增加 SWAP 的代码逻辑
    # 示例：增加一个 512MB 的 SWAP 文件
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$swap_add_size
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "已成功增加 $swap_add_size MB 的 SWAP。"
    ;;
  2)
    # 减少 SWAP
    read -p "请输入减少的 SWAP 大小 (单位 MB): " swap_reduce_size
    echo "正在减少 $swap_reduce_size MB 的 SWAP..."
    # 减少 SWAP 的代码逻辑
    # 示例：删除或减少 SWAP 文件
    sudo swapoff /swapfile
    sudo rm /swapfile
    echo "已成功减少 $swap_reduce_size MB 的 SWAP。"
    ;;
  3)
    # 不调整 SWAP
    echo "您选择不调整 SWAP。"
    ;;
  *)
    echo "无效选项，退出程序。"
    ;;
esac

# 提示当前的内存和 SWAP 信息
echo "当前的内存和 SWAP 配置："
free -h

# 提示按 Enter 键继续
read -p "已显示当前的内存和 SWAP 配置，按 Enter 键继续..."

#!/bin/bash

# 检查是否已启用 BBR
check_bbr() {
    sysctl net.ipv4.tcp_congestion_control | grep -q 'bbr'
    return $?
}

# 显示当前的 BBR 配置和加速方案
show_bbr_info() {
    # 显示当前的 TCP 拥塞控制算法
    echo "当前系统的 TCP 拥塞控制算法: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
    
    # 显示当前的默认队列调度器
    echo "当前系统的默认队列调度器: $(sysctl net.core.default_qdisc | awk '{print $3}')"
}

# 启用 BBR+FQ
enable_bbr_fq() {
    echo "正在启用 BBR 和 BBR+FQ 加速方案..."

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

    echo "BBR 和 BBR+FQ 已成功启用！"
}

# 主程序
echo "检测是否启用 BBR 加速..."

# 检查 BBR 是否已经启用
check_bbr
if [ $? -eq 0 ]; then
    echo "BBR 已启用，当前配置如下："
    show_bbr_info
    echo "BBR 已经启用，跳过启用过程，继续执行脚本的其他部分..."
else
    # 显示当前 BBR 配置和加速方案
    show_bbr_info

    # 询问用户是否启用 BBR+FQ
    echo "BBR 未启用，您可以选择启用 BBR+FQ 加速方案："
    echo "1. 启用 BBR+FQ"
    echo "2. 不启用，跳过"
    read -p "请输入您的选择 (1 或 2): " choice

    if [[ "$choice" == "1" ]]; then
        # 用户选择启用 BBR+FQ
        enable_bbr_fq
        echo "BBR+FQ 已启用，您需要重启系统才能生效。"
        echo "请通过运行 'sudo reboot' 命令重启系统，或者稍后手动重启。"
    elif [[ "$choice" == "2" ]]; then
        # 用户选择不启用
        echo "维持当前配置，跳过 BBR 加速启用部分，继续执行脚本的其他部分。"
    else
        echo "无效的选择，跳过此部分。"
    fi
fi

# 继续执行脚本的后续部分...
echo "继续执行脚本的其他部分..."

# 四、清理系统垃圾
echo "开始清理系统垃圾..."

# 对于基于 Debian/Ubuntu 的系统，清理 apt 缓存
if command -v apt &> /dev/null; then
  echo "正在清理 APT 缓存..."
  apt clean
  apt autoclean
  apt autoremove -y
fi

# 对于基于 CentOS/RHEL 的系统，清理 YUM 缓存
if command -v yum &> /dev/null; then
  echo "正在清理 YUM 缓存..."
  yum clean all
  yum autoremove -y
fi

# 清理临时文件
echo "正在清理临时文件..."
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "系统垃圾清理完成！"

# 五、清理日志文件（用户选择清理时间范围）
echo "请选择要清理的日志文件时间范围："
echo "1) 清除一周内的日志"
echo "2) 清除一月内的日志"
echo "3) 清除半年的日志"
echo "4) 清除所有日志"
echo "5) 不用清理"

read -p "请输入选项 (1/2/3/4/5): " log_choice

case $log_choice in
  1)
    echo "正在清除一周内的日志..."
    find /var/log -type f -name '*.log' -mtime +7 -exec rm -f {} \;
    ;;
  2)
    echo "正在清除一月内的日志..."
    find /var/log -type f -name '*.log' -mtime +30 -exec rm -f {} \;
    ;;
  3)
    echo "正在清除半年的日志..."
    find /var/log -type f -name '*.log' -mtime +180 -exec rm -f {} \;
    ;;
  4)
    echo "正在清除所有日志..."
    find /var/log -type f -name '*.log' -exec rm -f {} \;
    ;;
  5)
    echo "不清理日志文件，跳过此步骤。"
    ;;
  *)
    echo "无效选项，跳过清理日志文件。"
    ;;
esac

echo "日志清理完成！"

# 六、系统优化完成提示
echo "系统优化完成！"

echo "本次优化包括："
echo "1) 更新了系统并安装了常用组件（如 sudo, wget, curl, fail2ban, ufw）。"
echo "2) 设置了SSH端口，增强了远程登录安全性。"
echo "3) 启用了防火墙并配置了常用端口，特别是 SSH 服务端口。"
echo "4) 启用了 Fail2Ban 防护，增强了系统安全性。"
echo "5) 根据您的选择，已调整系统时区设置。"
echo "6) 根据您的选择，已调整或配置了 SWAP 大小。"
echo "7) 根据您的选择，已设置BBR。"
echo "8) 清理了系统垃圾文件和临时文件。"
echo "9) 根据您的选择，已清理了不需要的系统日志文件。"


echo "所有操作已完成，系统已经优化并增强了安全性！"
echo "如果设置了打开BBR，需重启后生效，可以输入reboot"
echo "如果修改了SSH端口，记得在SSH工具上修改为新的端口，否则无法连接"
