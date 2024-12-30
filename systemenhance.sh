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

#!/bin/bash

# -------------------------
# 修改时区功能
# -------------------------
echo "当前系统的时区是：$(timedatectl | grep 'Time zone' | awk '{print $3}')"
echo "以下是可用的时区及代表城市，选择一个时区来设置："
echo "1) 东八区 (Asia/Shanghai)"
echo "2) 美国东部时间 (America/New_York)"
echo "3) 美国西部时间 (America/Los_Angeles)"
echo "4) 欧洲中央时间 (Europe/Paris)"
echo "5) 英国时间 (Europe/London)"
echo "6) 澳大利亚东部时间 (Australia/Sydney)"
echo "7) 日本时间 (Asia/Tokyo)"
echo "8) 印度标准时间 (Asia/Kolkata)"
echo "9) 维持当前时区"

read -p "请输入你想选择的时区编号 (1-9): " timezone_choice

case $timezone_choice in
  1)
    new_timezone="Asia/Shanghai"
    ;;
  2)
    new_timezone="America/New_York"
    ;;
  3)
    new_timezone="America/Los_Angeles"
    ;;
  4)
    new_timezone="Europe/Paris"
    ;;
  5)
    new_timezone="Europe/London"
    ;;
  6)
    new_timezone="Australia/Sydney"
    ;;
  7)
    new_timezone="Asia/Tokyo"
    ;;
  8)
    new_timezone="Asia/Kolkata"
    ;;
  9)
    echo "您选择维持当前时区，跳过时区设置。"
    exit 0
    ;;
  *)
    echo "无效选择，请选择1到9之间的编号。"
    exit 1
    ;;
esac

# 设置时区
if timedatectl set-timezone "$new_timezone"; then
  echo "时区已成功更改为：$new_timezone"
else
  echo "无法设置时区，请检查时区是否正确。"
  exit 1
fi

# -------------------------
# 调整 SWAP 大小功能
# -------------------------
echo "检查当前 swap 配置..."

# 查看当前 swap
current_swap=$(swapon --show=NAME,SIZE --bytes | grep -E "swap" | awk '{print $2}' | numfmt --to=iec)

if [ -z "$current_swap" ]; then
  echo "当前没有配置 swap 分区。"
else
  echo "当前 swap 大小为：$current_swap"
fi

echo "请选择要执行的操作："
echo "1) 增加 swap 大小"
echo "2) 减少 swap 大小"
echo "3) 不做任何更改"

read -p "请输入选项 (1/2/3): " swap_choice

case $swap_choice in
  1)
    read -p "请输入要增加的 swap 大小（单位：MB）： " swap_increase
    swap_size=$(($swap_increase * 1024 * 1024)) # 转换为字节

    # 创建一个新的 swap 文件
    echo "正在增加 swap 大小 $swap_increase MB..."
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$swap_increase status=progress
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile

    # 永久生效（添加到 /etc/fstab）
    if ! grep -qs '/swapfile' /etc/fstab; then
      echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
    fi

    echo "swap 大小已增加 $swap_increase MB，当前 swap 大小为：$(swapon --show=NAME,SIZE --bytes | grep -E 'swap' | awk '{print $2}' | numfmt --to=iec)"
    ;;
  2)
    read -p "请输入要减少的 swap 大小（单位：MB）： " swap_decrease
    swap_size=$(($swap_decrease * 1024 * 1024)) # 转换为字节

    # 检查是否足够减少
    current_swap_size=$(swapon --show=NAME,SIZE --bytes | grep -E 'swap' | awk '{print $2}')
    if [ "$current_swap_size" -lt "$swap_size" ]; then
      echo "当前 swap 大小不足以减少 $swap_decrease MB。"
      exit 1
    fi

    # 关闭当前的 swap 并减少大小
    echo "正在减少 swap 大小 $swap_decrease MB..."
    sudo swapoff -v /swapfile

    # 调整 swap 大小（通过创建新的 swap 文件）
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$((current_swap_size / 1024 / 1024 - swap_decrease)) status=progress
    sudo mkswap /swapfile
    sudo swapon /swapfile

    echo "swap 大小已减少 $swap_decrease MB，当前 swap 大小为：$(swapon --show=NAME,SIZE --bytes | grep -E 'swap' | awk '{print $2}' | numfmt --to=iec)"
    ;;
  3)
    echo "您选择不做任何更改，退出程序。"
    ;;
  *)
    echo "无效的选择，退出程序。"
    exit 1
    ;;
esac


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

echo "所有操作已完成，系统已经优化并增强了安全性！"
