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

# 检测当前 SSH 服务是否启用
echo "正在检测 SSH 服务状态..."
if ! systemctl is-active --quiet sshd; then
  echo "当前未启用 SSH 服务，跳过检查端口的步骤。"
else
  # 检测当前所有的 SSH 服务端口
  echo "正在检测当前 SSH 服务端口..."
  # 尝试从 SSH 配置文件中获取端口
  ssh_config_file="/etc/ssh/sshd_config"
  ssh_ports=$(grep -E "^Port " "$ssh_config_file" | awk '{print $2}' | sort | uniq)

  # 如果配置文件中没有找到端口，则默认使用 22
  if [ -z "$ssh_ports" ]; then
    echo "未在 SSH 配置文件中找到端口设置，默认端口为 22。"
    read -p "是否继续执行脚本？(y/n): " choice
    if [[ "$choice" != "y" && "$choice" != "Y" ]]; then
      echo "脚本执行已取消。"
      exit 1
    fi
    ssh_ports="22"
  else
    echo "检测到以下 SSH 端口："
    echo "$ssh_ports"
    echo
    read -p "请选择要保留的 SSH 端口（输入端口号）： " selected_port

    # 检查输入端口是否有效
    if ! echo "$ssh_ports" | grep -q "$selected_port"; then
      echo "错误：所选端口无效，脚本退出。"
      exit 1
    fi

    echo "您选择保留的 SSH 端口为: $selected_port"
    
    # 关闭其他 SSH 端口
    for port in $ssh_ports; do
      if [ "$port" != "$selected_port" ]; then
        echo "正在关闭 SSH 端口 $port..."
        ufw deny $port/tcp
      fi
    done
  fi
fi

# 启用防火墙
echo "正在启用防火墙 (ufw)..."
ufw enable

# 开放所选的 SSH 端口
if [ "$ssh_ports" != "22" ]; then
  echo "正在开放所选的 SSH 端口 $selected_port..."
  ufw allow $selected_port/tcp
else
  echo "默认端口 22 已开放"
fi

# 检测其他常用服务的端口并开放
echo "正在检测并开放常用服务端口..."
ss -tuln | grep -E "tcp|udp" | awk '{print $4}' | cut -d: -f2 | sort | uniq | while read port; do
  if ! ufw status | grep -q "$port"; then
    echo "正在开放端口 $port..."
    ufw allow $port/tcp
  fi
done

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
    echo "您选择不清理日志，跳过此步骤。"
    ;;
  *)
    echo "无效选项，退出脚本。"
    exit 1
    ;;
esac

echo "日志文件清理完成！"

# 最终提示
echo "所有操作已完成！"
