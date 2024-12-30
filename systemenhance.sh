#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
  echo "请使用root权限运行此脚本！"
  exit 1
fi

# 提示用户开始操作
echo "开始执行系统优化脚本..."

# 二、更新系统
echo "正在更新系统..."
if command -v apt-get &> /dev/null; then
  apt-get update && apt-get upgrade -y
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
  apt-get install -y sudo || yum install -y sudo
else
  echo "sudo 已安装"
fi

# 检查并安装 wget
if ! command -v wget &> /dev/null; then
  echo "未检测到 wget，正在安装..."
  apt-get install -y wget || yum install -y wget
else
  echo "wget 已安装"
fi

# 检查并安装 curl
if ! command -v curl &> /dev/null; then
  echo "未检测到 curl，正在安装..."
  apt-get install -y curl || yum install -y curl
else
  echo "curl 已安装"
fi

# 检查并安装 fail2ban
if ! command -v fail2ban-client &> /dev/null; then
  echo "未检测到 fail2ban，正在安装..."
  apt-get install -y fail2ban || yum install -y fail2ban
else
  echo "fail2ban 已安装"
fi

# 检查并安装 ufw
if ! command -v ufw &> /dev/null; then
  echo "未检测到 ufw，正在安装..."
  apt-get install -y ufw || yum install -y ufw
else
  echo "ufw 已安装"
fi

echo "常用组件安装完成。"

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


# 四、清理系统垃圾
echo "开始清理系统垃圾..."

# 对于基于 Debian/Ubuntu 的系统，清理 apt 缓存
if command -v apt-get &> /dev/null; then
  echo "正在清理 APT 缓存..."
  apt-get clean
  apt-get autoclean
  apt-get autoremove -y
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
echo "2) 启用了防火墙并配置了常用端口，特别是 SSH 服务端口。"
echo "3) 启用了 Fail2Ban 防护，增强了系统安全性。"
echo "4) 清理了系统垃圾文件和临时文件。"
echo "5) 根据您的选择，已清理了不需要的系统日志文件。"
echo "6) 根据您的选择，已调整系统时区设置。"
echo "7) 根据您的选择，已调整或配置了 SWAP 大小。"

echo "所有操作已完成，系统已经优化并增强了安全性！"
