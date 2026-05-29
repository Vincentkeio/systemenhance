#!/usr/bin/env bash

# =============================================
#        系统优化与安全增强脚本 修复增强版
#        保留原功能思路，增强兼容性与防锁死
# =============================================

# 不使用 set -e：系统增强脚本应尽量继续执行后续模块，而不是某一步失败就整脚本退出
set -uo pipefail

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
NC="\033[0m"

SCRIPT_NAME="system_enhance_fixed"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
BACKUP_DIR="/root/${SCRIPT_NAME}_backup_$(date +%Y%m%d_%H%M%S)"
BBR_MODIFIED=false
SSH_SELECTED_PORT=""
SSH_OLD_PORT=""
PKG_MANAGER=""
OS_ID="unknown"
OS_LIKE=""
OS_NAME="unknown"
OS_VERSION="unknown"
OS_CODENAME="unknown"
SYSTEM_ARCH="$(uname -m 2>/dev/null || echo unknown)"
KERNEL_VERSION="$(uname -r 2>/dev/null || echo unknown)"

print_separator() { printf "%b============================================%b\n" "$CYAN" "$NC"; }
print_info() { printf "%b⚙️  %s%b\n" "$BLUE" "$*" "$NC"; }
print_success() { printf "%b✔️  %s%b\n" "$GREEN" "$*" "$NC"; }
print_warning() { printf "%b⚠️  %s%b\n" "$YELLOW" "$*" "$NC"; }
print_error() { printf "%b❌  %s%b\n" "$RED" "$*" "$NC"; }

pause_line() { echo; }

ask_yes_no() {
    # 用法：ask_yes_no "问题" "Y"；第二参数 Y 表示默认是，N 表示默认否
    local prompt="$1"
    local default="${2:-N}"
    local answer suffix
    if [[ "$default" =~ ^[Yy]$ ]]; then
        suffix="Y/n"
    else
        suffix="y/N"
    fi
    read -r -p "$prompt ($suffix): " answer || answer=""
    if [[ -z "$answer" ]]; then
        [[ "$default" =~ ^[Yy]$ ]]
        return $?
    fi
    [[ "$answer" =~ ^[Yy]$ ]]
}

run_cmd() {
    print_info "执行：$*"
    "$@"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        print_warning "命令执行失败，返回码：$rc"
    fi
    return $rc
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        print_separator
        print_error "请使用 root 权限运行此脚本。"
        print_separator
        exit 1
    fi
}

init_log_and_backup() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null && exec > >(tee -a "$LOG_FILE") 2>&1 || true
}

backup_file() {
    local file="$1"
    [[ -e "$file" ]] || return 0
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    local safe_name
    safe_name="$(echo "$file" | sed 's#/#_#g')"
    cp -a "$file" "$BACKUP_DIR/${safe_name}.bak" 2>/dev/null && print_warning "已备份：$file -> $BACKUP_DIR/${safe_name}.bak"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

get_system_info() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
        OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
        OS_VERSION="${VERSION_ID:-${VERSION:-unknown}}"
        OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
    elif command_exists lsb_release; then
        OS_ID="$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        OS_NAME="$(lsb_release -ds 2>/dev/null | tr -d '"')"
        OS_VERSION="$(lsb_release -rs 2>/dev/null)"
        OS_CODENAME="$(lsb_release -cs 2>/dev/null)"
    elif [[ -r /etc/debian_version ]]; then
        OS_ID="debian"
        OS_NAME="Debian"
        OS_VERSION="$(cat /etc/debian_version)"
        OS_CODENAME="unknown"
    fi

    case "$OS_ID $OS_LIKE" in
        *debian*|*ubuntu*) PKG_MANAGER="apt" ;;
        *rhel*|*fedora*|*centos*|*rocky*|*almalinux*)
            if command_exists dnf; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi
            ;;
        *alpine*) PKG_MANAGER="apk" ;;
        *suse*) PKG_MANAGER="zypper" ;;
        *arch*) PKG_MANAGER="pacman" ;;
        *)
            if command_exists apt-get; then PKG_MANAGER="apt"
            elif command_exists dnf; then PKG_MANAGER="dnf"
            elif command_exists yum; then PKG_MANAGER="yum"
            elif command_exists apk; then PKG_MANAGER="apk"
            elif command_exists zypper; then PKG_MANAGER="zypper"
            elif command_exists pacman; then PKG_MANAGER="pacman"
            else PKG_MANAGER="unknown"
            fi
            ;;
    esac
}

show_system_info() {
    print_separator
    printf "%b📋 系统信息：%b\n" "$PURPLE" "$NC"
    printf "%b操作系统 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$OS_NAME" "$NC"
    printf "%b版本号   :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$OS_VERSION" "$NC"
    printf "%b代号     :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$OS_CODENAME" "$NC"
    printf "%b内核版本 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$KERNEL_VERSION" "$NC"
    printf "%b系统架构 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$SYSTEM_ARCH" "$NC"
    printf "%b包管理器 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$PKG_MANAGER" "$NC"
    printf "%b日志文件 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$LOG_FILE" "$NC"
    printf "%b备份目录 :%b %b%s%b\n" "$WHITE" "$NC" "$GREEN" "$BACKUP_DIR" "$NC"
    print_separator
}

pkg_update() {
    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            run_cmd apt-get update
            run_cmd apt-get upgrade -y
            ;;
        dnf) run_cmd dnf -y upgrade ;;
        yum) run_cmd yum -y update ;;
        apk) run_cmd apk update && run_cmd apk upgrade ;;
        zypper) run_cmd zypper --non-interactive refresh && run_cmd zypper --non-interactive update ;;
        pacman) run_cmd pacman -Syu --noconfirm ;;
        *) print_warning "未识别包管理器，跳过系统更新。" ;;
    esac
}

pkg_install() {
    local pkgs=("$@")
    [[ ${#pkgs[@]} -gt 0 ]] || return 0
    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            run_cmd apt-get install -y "${pkgs[@]}"
            ;;
        dnf) run_cmd dnf install -y "${pkgs[@]}" ;;
        yum) run_cmd yum install -y "${pkgs[@]}" ;;
        apk) run_cmd apk add --no-cache "${pkgs[@]}" ;;
        zypper) run_cmd zypper --non-interactive install -y "${pkgs[@]}" ;;
        pacman) run_cmd pacman -S --noconfirm --needed "${pkgs[@]}" ;;
        *) print_warning "未识别包管理器，无法自动安装：${pkgs[*]}"; return 1 ;;
    esac
}

install_common_components() {
    print_separator
    print_info "检查并安装常用组件。"
    print_separator

    local pkgs=()
    local ssh_pkg="openssh-server"
    local ip_pkg="iproute2"
    local procps_pkg="procps"

    case "$PKG_MANAGER" in
        apk)
            ssh_pkg="openssh"
            procps_pkg="procps-ng"
            ;;
        pacman)
            ssh_pkg="openssh"
            procps_pkg="procps-ng"
            ;;
    esac

    command_exists sudo || pkgs+=(sudo)
    command_exists wget || pkgs+=(wget)
    command_exists curl || pkgs+=(curl)
    command_exists ip || pkgs+=("$ip_pkg")
    command_exists ss || pkgs+=("$ip_pkg")
    command_exists sysctl || pkgs+=("$procps_pkg")
    command_exists sshd || pkgs+=("$ssh_pkg")
    command_exists fail2ban-client || pkgs+=(fail2ban)
    command_exists ufw || pkgs+=(ufw)
    command_exists timedatectl || true

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        print_success "常用组件已基本齐全。"
        return 0
    fi

    print_info "准备安装：${pkgs[*]}"
    pkg_install "${pkgs[@]}"
    print_success "常用组件检查完成。"
}

service_exists_systemd() { systemctl list-unit-files "$1.service" >/dev/null 2>&1 || systemctl status "$1" >/dev/null 2>&1; }

service_is_active() {
    local svc="$1"
    if command_exists systemctl; then
        systemctl is-active --quiet "$svc" 2>/dev/null && return 0
    fi
    if command_exists rc-service; then
        rc-service "$svc" status >/dev/null 2>&1 && return 0
    fi
    if command_exists service; then
        service "$svc" status >/dev/null 2>&1 && return 0
    fi
    pgrep -x "$svc" >/dev/null 2>&1
}

service_enable_start() {
    local svc="$1"
    if command_exists systemctl; then
        systemctl enable "$svc" >/dev/null 2>&1 || true
        systemctl start "$svc" >/dev/null 2>&1 || true
    elif command_exists rc-update; then
        rc-update add "$svc" default >/dev/null 2>&1 || true
        rc-service "$svc" start >/dev/null 2>&1 || true
    elif command_exists service; then
        service "$svc" start >/dev/null 2>&1 || true
    fi
}

service_restart() {
    local svc="$1"
    if command_exists systemctl; then
        systemctl restart "$svc" >/dev/null 2>&1
    elif command_exists rc-service; then
        rc-service "$svc" restart >/dev/null 2>&1
    elif command_exists service; then
        service "$svc" restart >/dev/null 2>&1
    else
        return 1
    fi
}

detect_ssh_service() {
    if service_is_active sshd || [[ -f /etc/init.d/sshd ]]; then echo "sshd"; return; fi
    if service_is_active ssh || [[ -f /etc/init.d/ssh ]]; then echo "ssh"; return; fi
    if command_exists systemctl; then
        if service_exists_systemd sshd; then echo "sshd"; return; fi
        if service_exists_systemd ssh; then echo "ssh"; return; fi
    fi
    echo "sshd"
}

get_ssh_config_file() {
    if [[ -f /etc/ssh/sshd_config ]]; then echo "/etc/ssh/sshd_config"; return; fi
    echo "/etc/ssh/sshd_config"
}

get_ssh_ports_from_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2}' "$file" | sort -n | uniq
    fi
}

get_listening_ports() {
    # 输出 protocol:port，例如 tcp:22、udp:53
    if command_exists ss; then
        ss -H -lntu 2>/dev/null | awk '{proto=$1; addr=$5; gsub(/\[|\]/,"",addr); n=split(addr,a,":"); port=a[n]; if (port ~ /^[0-9]+$/) print proto":"port}' | sort -u
    elif command_exists netstat; then
        netstat -lntu 2>/dev/null | awk 'NR>2 {proto=$1; addr=$4; n=split(addr,a,":"); port=a[n]; if (port ~ /^[0-9]+$/) print proto":"port}' | sort -u
    fi
}

port_is_listening() {
    local port="$1"
    get_listening_ports | grep -Eq "^(tcp|udp):${port}$"
}

firewall_type() {
    if command_exists ufw; then echo "ufw"; return; fi
    if command_exists firewall-cmd; then echo "firewalld"; return; fi
    echo "none"
}

firewall_is_active() {
    case "$(firewall_type)" in
        ufw) ufw status 2>/dev/null | grep -qi "Status: active" ;;
        firewalld) command_exists systemctl && systemctl is-active --quiet firewalld 2>/dev/null ;;
        *) return 1 ;;
    esac
}

firewall_enable_safe() {
    local ssh_port="$1"
    local fw
    fw="$(firewall_type)"
    case "$fw" in
        ufw)
            ufw allow "${ssh_port}/tcp" >/dev/null 2>&1 || true
            ufw --force enable >/dev/null 2>&1 || true
            ;;
        firewalld)
            service_enable_start firewalld
            firewall-cmd --permanent --add-port="${ssh_port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
        none)
            print_warning "未检测到 ufw/firewalld，跳过防火墙启用。"
            return 1
            ;;
    esac
}

firewall_allow_port() {
    local port="$1" proto="${2:-tcp}"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    case "$(firewall_type)" in
        ufw) ufw allow "${port}/${proto}" >/dev/null 2>&1 ;;
        firewalld)
            service_enable_start firewalld
            firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            ;;
        *) print_warning "未检测到受支持防火墙，请手动放行 ${port}/${proto}。"; return 1 ;;
    esac
}

firewall_delete_allow_port() {
    local port="$1" proto="${2:-tcp}"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    case "$(firewall_type)" in
        ufw) ufw delete allow "${port}/${proto}" >/dev/null 2>&1 || true ;;
        firewalld)
            firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            ;;
    esac
}

firewall_reload() {
    case "$(firewall_type)" in
        ufw) ufw reload >/dev/null 2>&1 || true ;;
        firewalld) firewall-cmd --reload >/dev/null 2>&1 || true ;;
    esac
}

show_firewall_status() {
    case "$(firewall_type)" in
        ufw) ufw status verbose 2>/dev/null || true ;;
        firewalld) firewall-cmd --list-all 2>/dev/null || true ;;
        *) print_warning "无受支持防火墙状态可显示。" ;;
    esac
}

install_and_start_ssh() {
    local svc
    svc="$(detect_ssh_service)"
    if command_exists sshd; then
        print_success "OpenSSH 服务端已安装。"
    else
        print_warning "未检测到 OpenSSH 服务端，正在安装。"
        case "$PKG_MANAGER" in
            apk|pacman) pkg_install openssh ;;
            *) pkg_install openssh-server ;;
        esac
    fi
    service_enable_start "$svc"
    if service_is_active "$svc" || pgrep -x sshd >/dev/null 2>&1; then
        print_success "SSH 服务已启动。"
    else
        print_warning "SSH 服务未确认启动，请稍后手动检查。"
    fi
}

configure_ssh_port() {
    print_separator
    print_info "检测并配置 SSH 端口。"
    print_separator

    install_and_start_ssh

    local ssh_config_file ssh_service current_ports current_port modify_choice new_port
    ssh_config_file="$(get_ssh_config_file)"
    ssh_service="$(detect_ssh_service)"

    if [[ ! -f "$ssh_config_file" ]]; then
        print_error "找不到 SSH 配置文件：$ssh_config_file，跳过 SSH 端口配置。"
        return 1
    fi

    current_ports="$(get_ssh_ports_from_config "$ssh_config_file")"
    if [[ -z "$current_ports" ]]; then
        current_port="22"
        print_warning "配置文件未显式设置 Port，按默认 22 处理。"
    else
        current_port="$(echo "$current_ports" | head -n 1)"
    fi
    SSH_OLD_PORT="$current_port"
    SSH_SELECTED_PORT="$current_port"

    printf "%b当前 SSH 配置端口：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$(echo "$current_ports" | tr '\n' ' ' | sed 's/[[:space:]]*$//')${current_ports:+ }默认:${current_port}" "$NC"

    if ask_yes_no "是否修改 SSH 端口" "N"; then
        read -r -p "请输入新的 SSH 端口号 (1-65535): " new_port || new_port=""
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || (( new_port < 1 || new_port > 65535 )); then
            print_error "端口无效，跳过 SSH 端口修改。"
            return 1
        fi

        if (( new_port == 22 )); then
            print_warning "你选择了默认 22 端口。"
        fi

        # 防锁死顺序：先放行新端口，再改配置，再校验，再重启
        firewall_allow_port "$new_port" tcp || true
        backup_file "$ssh_config_file"

        if grep -Eq '^[#[:space:]]*Port[[:space:]]+' "$ssh_config_file"; then
            # 用 awk 替换第一条 Port，并注释其他重复 Port；避免使用 GNU sed 专属的 0,/regex/ 语法，提升 Alpine/BusyBox 兼容性。
            awk -v new_port="$new_port" '
                BEGIN { done=0 }
                /^[#[:space:]]*Port[[:space:]]+[0-9]+/ {
                    if (done==0) { print "Port " new_port; done=1; next }
                    print "# " $0 "    # disabled by system_enhance_fixed"; next
                }
                { print }
            ' "$ssh_config_file" > "${ssh_config_file}.tmp" && mv "${ssh_config_file}.tmp" "$ssh_config_file"
        else
            printf "\nPort %s\n" "$new_port" >> "$ssh_config_file"
        fi

        if command_exists sshd; then
            if ! sshd -t -f "$ssh_config_file" 2>/tmp/sshd_config_test.err; then
                print_error "SSH 配置校验失败，正在回滚。"
                cat /tmp/sshd_config_test.err 2>/dev/null || true
                local bak
                bak="$BACKUP_DIR/$(echo "$ssh_config_file" | sed 's#/#_#g').bak"
                [[ -f "$bak" ]] && cp -a "$bak" "$ssh_config_file"
                return 1
            fi
        fi

        if service_restart "$ssh_service" || service_restart ssh || service_restart sshd; then
            print_success "SSH 服务已重启。"
        else
            print_warning "SSH 服务重启未确认成功，请手动执行：systemctl restart ${ssh_service}"
        fi

        SSH_SELECTED_PORT="$new_port"
        print_success "SSH 端口已设置为：$new_port"
    else
        print_warning "跳过 SSH 端口修改。"
    fi

    firewall_allow_port "$SSH_SELECTED_PORT" tcp || true

    if port_is_listening "$SSH_SELECTED_PORT"; then
        print_success "检测到 SSH 端口 $SSH_SELECTED_PORT 正在监听。"
    else
        print_warning "未检测到端口 $SSH_SELECTED_PORT 监听。若你刚修改了端口，请另开一个 SSH 窗口测试后再关闭当前连接。"
    fi
}

select_keep_ssh_port_and_close_others() {
    print_separator
    print_info "检测当前 SSH 配置端口，并可选择关闭其他 SSH 端口防火墙规则。"
    print_separator

    local file ports count selected_option selected_port port i
    file="$(get_ssh_config_file)"
    ports="$(get_ssh_ports_from_config "$file")"
    [[ -n "$ports" ]] || ports="22"

    printf "%b检测到 SSH 端口：%b\n" "$WHITE" "$NC"
    i=1
    while read -r port; do
        [[ -n "$port" ]] || continue
        printf "%d) %b%s%b\n" "$i" "$GREEN" "$port" "$NC"
        i=$((i+1))
    done <<< "$ports"
    count=$((i-1))

    if (( count <= 1 )); then
        selected_port="$(echo "$ports" | head -n 1)"
        SSH_SELECTED_PORT="${SSH_SELECTED_PORT:-$selected_port}"
        print_success "仅检测到一个 SSH 端口：$selected_port，无需关闭其他 SSH 端口。"
        firewall_allow_port "$selected_port" tcp || true
        return 0
    fi

    if ! ask_yes_no "是否只保留一个 SSH 端口，并删除其他端口的防火墙放行规则" "N"; then
        print_warning "跳过关闭其他 SSH 端口。"
        return 0
    fi

    read -r -p "请输入要保留的端口序号: " selected_option || selected_option=""
    if ! [[ "$selected_option" =~ ^[0-9]+$ ]] || (( selected_option < 1 || selected_option > count )); then
        print_error "选择无效，跳过。"
        return 1
    fi

    selected_port="$(echo "$ports" | sed -n "${selected_option}p")"
    SSH_SELECTED_PORT="$selected_port"
    firewall_allow_port "$selected_port" tcp || true

    while read -r port; do
        [[ -n "$port" ]] || continue
        if [[ "$port" != "$selected_port" ]]; then
            print_warning "删除防火墙中 SSH 端口 $port/tcp 的放行规则。"
            firewall_delete_allow_port "$port" tcp || true
        fi
    done <<< "$ports"
    firewall_reload
}

ensure_firewall() {
    print_separator
    print_info "检测防火墙状态。"
    print_separator

    local fw ssh_port
    fw="$(firewall_type)"
    ssh_port="${SSH_SELECTED_PORT:-22}"

    if [[ "$fw" == "none" ]]; then
        print_warning "未检测到 ufw/firewalld。"
        if ask_yes_no "是否尝试安装 ufw" "N"; then
            pkg_install ufw
            fw="$(firewall_type)"
        fi
    fi

    if firewall_is_active; then
        print_success "防火墙已启用：$(firewall_type)"
        firewall_allow_port "$ssh_port" tcp || true
        return 0
    fi

    print_warning "防火墙当前未启用。启用前会先放行 SSH 端口 $ssh_port/tcp。"
    if ask_yes_no "是否启用防火墙" "N"; then
        firewall_enable_safe "$ssh_port"
        if firewall_is_active; then
            print_success "防火墙已启用，并已放行 SSH 端口 $ssh_port/tcp。"
        else
            print_warning "防火墙启用未确认成功，请手动检查。"
        fi
    else
        print_warning "跳过启用防火墙。"
    fi
}

open_listening_service_ports() {
    print_separator
    print_info "检测并可选开放当前正在监听的服务端口。"
    print_separator

    local ports item proto port
    ports="$(get_listening_ports)"
    if [[ -z "$ports" ]]; then
        print_warning "未检测到监听端口，或 ss/netstat 不可用。"
        return 0
    fi

    echo "$ports" | sed 's/^/  - /'
    print_warning "注意：开放所有监听端口可能降低安全性。建议只在纯新机初始化或明确知道服务用途时使用。"
    if ! ask_yes_no "是否开放以上所有监听端口" "N"; then
        print_warning "跳过开放所有监听端口。"
        return 0
    fi

    while IFS=: read -r proto port; do
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        firewall_allow_port "$port" "$proto" || true
    done <<< "$ports"
    firewall_reload
    print_success "已处理当前监听端口的防火墙放行规则。"
}

setup_fail2ban() {
    print_separator
    print_info "启用 Fail2Ban 防护。"
    print_separator

    if ! command_exists fail2ban-client; then
        print_warning "未检测到 fail2ban，正在安装。"
        pkg_install fail2ban
    fi

    local jail_dir jail_file ssh_port
    jail_dir="/etc/fail2ban/jail.d"
    jail_file="$jail_dir/sshd.local"
    ssh_port="${SSH_SELECTED_PORT:-22}"

    mkdir -p "$jail_dir" 2>/dev/null || true
    if [[ -d "$jail_dir" ]]; then
        backup_file "$jail_file"
        cat > "$jail_file" <<JAIL
[sshd]
enabled = true
port = ${ssh_port}
maxretry = 5
findtime = 10m
bantime = 1h
JAIL
        print_success "已写入 SSH 防护规则：$jail_file"
    fi

    service_enable_start fail2ban
    service_restart fail2ban || true

    if command_exists fail2ban-client; then
        fail2ban-client status 2>/dev/null || print_warning "Fail2Ban 状态读取失败，但安装/启动步骤已执行。"
    fi
}

get_ipv4_address() {
    if command_exists ip; then
        ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]; exit}'
    else
        hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -n 1
    fi
}

get_ipv6_address() {
    if command_exists ip; then
        ip -6 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); if(a[1] !~ /^fe80/ && a[1] != "::1") {print a[1]; exit}}'
    else
        hostname -I 2>/dev/null | tr ' ' '\n' | grep ':' | grep -vE '^fe80|^::1' | head -n 1
    fi
}

ping_test() {
    local mode="$1" host="$2"
    if [[ "$mode" == "4" ]]; then
        ping -4 -c 1 -W 3 "$host" >/dev/null 2>&1
    else
        ping -6 -c 1 -W 3 "$host" >/dev/null 2>&1
    fi
}

set_gai_ipv4_priority() {
    backup_file /etc/gai.conf
    touch /etc/gai.conf
    sed -i '/^[[:space:]]*precedence[[:space:]]*::ffff:0:0\/96[[:space:]]*/d' /etc/gai.conf
    printf "precedence ::ffff:0:0/96  100\n" >> /etc/gai.conf
}

set_gai_ipv6_priority() {
    backup_file /etc/gai.conf
    touch /etc/gai.conf
    sed -i '/^[[:space:]]*precedence[[:space:]]*::ffff:0:0\/96[[:space:]]*/d' /etc/gai.conf
}

check_and_set_network_priority() {
    print_separator
    print_info "IPv4/IPv6 网络检测与优先级配置。"
    print_separator

    local ipv4 ipv6 ipv4_valid=false ipv6_valid=false choice
    ipv4="$(get_ipv4_address || true)"
    ipv6="$(get_ipv6_address || true)"

    [[ -n "$ipv4" ]] && printf "%b本机 IPv4 地址：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$ipv4" "$NC" || print_warning "本机未检测到公网/全局 IPv4 地址。"
    [[ -n "$ipv6" ]] && printf "%b本机 IPv6 地址：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$ipv6" "$NC" || print_warning "本机未检测到公网/全局 IPv6 地址。"

    print_info "验证 IPv4 连通性。"
    if ping_test 4 1.1.1.1 || ping_test 4 8.8.8.8; then ipv4_valid=true; print_success "IPv4 可用。"; else print_warning "IPv4 不可用或 ICMP 被阻断。"; fi

    print_info "验证 IPv6 连通性。"
    if ping_test 6 2606:4700:4700::1111 || ping_test 6 2001:4860:4860::8888; then ipv6_valid=true; print_success "IPv6 可用。"; else print_warning "IPv6 不可用或 ICMP 被阻断。"; fi

    if [[ "$ipv4_valid" == true && "$ipv6_valid" == true ]]; then
        printf "%b双栈网络，请选择解析优先级：%b\n" "$YELLOW" "$NC"
        printf "1) %bIPv4 优先%b\n" "$GREEN" "$NC"
        printf "2) %bIPv6 优先%b\n" "$GREEN" "$NC"
        printf "3) %b取消%b\n" "$YELLOW" "$NC"
        read -r -p "请输入选项 (1/2/3): " choice || choice="3"
        case "$choice" in
            1) set_gai_ipv4_priority; print_success "已通过 /etc/gai.conf 设置 IPv4 优先。" ;;
            2) set_gai_ipv6_priority; print_success "已恢复默认 IPv6 优先策略。" ;;
            *) print_warning "跳过网络优先级修改。" ;;
        esac
    elif [[ "$ipv4_valid" == true ]]; then
        print_warning "当前更接近 IPv4-only 环境，跳过优先级选择。"
    elif [[ "$ipv6_valid" == true ]]; then
        print_warning "当前更接近 IPv6-only 环境，跳过优先级选择。"
    else
        print_warning "IPv4/IPv6 连通性都未验证成功，可能是 ICMP 被禁或网络异常。"
    fi
}

manage_dns() {
    print_separator
    print_info "当前系统 DNS 配置。"
    print_separator

    if [[ -f /etc/resolv.conf ]]; then
        echo "当前 /etc/resolv.conf nameserver："
        grep -E '^[[:space:]]*nameserver[[:space:]]+' /etc/resolv.conf || print_warning "未找到 nameserver。"
        if [[ -L /etc/resolv.conf ]]; then
            print_warning "/etc/resolv.conf 是符号链接，可能由 systemd-resolved、NetworkManager 或 resolvconf 管理。直接覆盖可能重启后失效。"
        fi
    else
        print_warning "/etc/resolv.conf 不存在。"
    fi

    if ! ask_yes_no "是否替换 /etc/resolv.conf DNS 配置" "N"; then
        print_info "保留现有 DNS。"
        return 0
    fi

    local ns1 ns2
    read -r -p "请输入第一个 nameserver，例如 1.1.1.1: " ns1 || ns1=""
    read -r -p "请输入第二个 nameserver，例如 8.8.8.8，可留空: " ns2 || ns2=""

    if [[ -z "$ns1" ]]; then
        print_error "nameserver 不能为空，跳过 DNS 修改。"
        return 1
    fi

    backup_file /etc/resolv.conf
    {
        printf "nameserver %s\n" "$ns1"
        [[ -n "$ns2" ]] && printf "nameserver %s\n" "$ns2"
    } > /etc/resolv.conf
    print_success "DNS 已更新。"
}

set_timezone_menu() {
    print_separator
    print_info "时区设置。"
    print_separator

    local current_tz choice tz
    if command_exists timedatectl; then
        current_tz="$(timedatectl show --property=Timezone --value 2>/dev/null || echo unknown)"
    elif [[ -f /etc/timezone ]]; then
        current_tz="$(cat /etc/timezone)"
    else
        current_tz="unknown"
    fi
    printf "%b当前时区：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$current_tz" "$NC"

    printf "%b请选择要设置的时区：%b\n" "$PURPLE" "$NC"
    printf "1) %b上海 Asia/Shanghai%b\n" "$GREEN" "$NC"
    printf "2) %b纽约 America/New_York%b\n" "$GREEN" "$NC"
    printf "3) %b洛杉矶 America/Los_Angeles%b\n" "$GREEN" "$NC"
    printf "4) %b伦敦 Europe/London%b\n" "$GREEN" "$NC"
    printf "5) %b东京 Asia/Tokyo%b\n" "$GREEN" "$NC"
    printf "6) %b巴黎 Europe/Paris%b\n" "$GREEN" "$NC"
    printf "7) %b曼谷 Asia/Bangkok%b\n" "$GREEN" "$NC"
    printf "8) %b悉尼 Australia/Sydney%b\n" "$GREEN" "$NC"
    printf "9) %b迪拜 Asia/Dubai%b\n" "$GREEN" "$NC"
    printf "10) %b里约热内卢 America/Sao_Paulo%b\n" "$GREEN" "$NC"
    printf "11) %b维持当前时区%b\n" "$YELLOW" "$NC"
    read -r -p "请输入选项 (1-11): " choice || choice="11"

    case "$choice" in
        1) tz="Asia/Shanghai" ;;
        2) tz="America/New_York" ;;
        3) tz="America/Los_Angeles" ;;
        4) tz="Europe/London" ;;
        5) tz="Asia/Tokyo" ;;
        6) tz="Europe/Paris" ;;
        7) tz="Asia/Bangkok" ;;
        8) tz="Australia/Sydney" ;;
        9) tz="Asia/Dubai" ;;
        10) tz="America/Sao_Paulo" ;;
        *) print_warning "维持当前时区。"; return 0 ;;
    esac

    if command_exists timedatectl; then
        timedatectl set-timezone "$tz" && print_success "时区已设置为 $tz。" || print_warning "timedatectl 设置失败。"
    elif [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        backup_file /etc/localtime
        ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
        echo "$tz" > /etc/timezone 2>/dev/null || true
        print_success "时区已设置为 $tz。"
    else
        print_warning "系统缺少 zoneinfo 或不支持自动设置，请手动设置时区：$tz"
    fi
}

manage_swap() {
    print_separator
    print_info "SWAP 管理。"
    print_separator

    free -h 2>/dev/null || true

    if ! ask_yes_no "是否调整/创建 SWAP" "N"; then
        print_warning "跳过 SWAP 管理。"
        return 0
    fi

    local new_swap_size swap_file existing_files existing_parts selected_swap_file
    read -r -p "请输入新的 SWAP 大小，单位 MB，例如 1024: " new_swap_size || new_swap_size=""
    if ! [[ "$new_swap_size" =~ ^[0-9]+$ ]] || (( new_swap_size <= 0 )); then
        print_error "SWAP 大小无效，跳过。"
        return 1
    fi

    if swapon --show=NAME,TYPE --noheadings >/dev/null 2>&1; then
        existing_files="$(swapon --show=NAME,TYPE --noheadings 2>/dev/null | awk '$2=="file"{print $1}')"
        existing_parts="$(swapon --show=NAME,TYPE --noheadings 2>/dev/null | awk '$2=="partition"{print $1}')"
    else
        # BusyBox/老系统 swapon 可能不支持 --show，回退到 /proc/swaps。
        existing_files="$(awk 'NR>1 && $2=="file"{print $1}' /proc/swaps 2>/dev/null)"
        existing_parts="$(awk 'NR>1 && $2=="partition"{print $1}' /proc/swaps 2>/dev/null)"
    fi

    if [[ -n "$existing_files" ]]; then
        selected_swap_file="$(echo "$existing_files" | head -n 1)"
        print_info "检测到 SWAP 文件：$selected_swap_file，将调整该文件。"
    elif [[ -n "$existing_parts" ]]; then
        print_warning "检测到 SWAP 分区：$(echo "$existing_parts" | tr '\n' ' ')"
        print_warning "自动 resize SWAP 分区存在误删分区风险，本增强版不自动改分区大小。"
        if ask_yes_no "是否改为创建 /swapfile 文件作为新的 SWAP" "Y"; then
            selected_swap_file="/swapfile"
        else
            print_warning "跳过 SWAP 修改。"
            return 0
        fi
    else
        selected_swap_file="/swapfile"
        print_info "未检测到 SWAP，将创建：$selected_swap_file"
    fi

    backup_file /etc/fstab
    swapoff "$selected_swap_file" >/dev/null 2>&1 || true
    rm -f "$selected_swap_file" 2>/dev/null || true

    if command_exists fallocate; then
        fallocate -l "${new_swap_size}M" "$selected_swap_file" 2>/dev/null || dd if=/dev/zero of="$selected_swap_file" bs=1M count="$new_swap_size" status=progress
    else
        dd if=/dev/zero of="$selected_swap_file" bs=1M count="$new_swap_size" status=progress
    fi

    chmod 600 "$selected_swap_file"
    mkswap "$selected_swap_file" || { print_error "mkswap 失败。"; return 1; }
    swapon "$selected_swap_file" || { print_error "swapon 失败。"; return 1; }

    if [[ -f /etc/fstab ]]; then
        awk -v swapfile="$selected_swap_file" '$1 != swapfile {print}' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
        printf "%s none swap defaults 0 0\n" "$selected_swap_file" >> /etc/fstab
    fi

    print_success "SWAP 已设置：$selected_swap_file ${new_swap_size}MB"
    free -h 2>/dev/null || true
}

set_sysctl_conf() {
    local key="$1" value="$2" file="/etc/sysctl.conf"
    backup_file "$file"
    touch "$file"
    sed -i "/^[[:space:]]*${key//./\.}[[:space:]]*=.*/d" "$file"
    printf "%s=%s\n" "$key" "$value" >> "$file"
}

show_bbr_info() {
    local cc qdisc
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    printf "%b当前 TCP 拥塞控制算法：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$cc" "$NC"
    printf "%b当前默认队列调度器  ：%b%b%s%b\n" "$WHITE" "$NC" "$GREEN" "$qdisc" "$NC"
}

enable_bbr_fq() {
    print_info "启用 BBR + FQ。"

    if command_exists modprobe; then
        modprobe tcp_bbr >/dev/null 2>&1 || true
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        print_warning "当前内核未显示支持 bbr，可能需要升级内核。跳过 BBR 设置。"
        return 1
    fi

    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || print_warning "设置 default_qdisc=fq 失败。"
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || { print_error "设置 tcp_congestion_control=bbr 失败。"; return 1; }

    set_sysctl_conf net.core.default_qdisc fq
    set_sysctl_conf net.ipv4.tcp_congestion_control bbr
    sysctl -p >/dev/null 2>&1 || true
    BBR_MODIFIED=true
    print_success "BBR + FQ 已启用。"
}

manage_bbr() {
    print_separator
    print_info "BBR 加速检测。"
    print_separator

    show_bbr_info
    if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -qw bbr; then
        print_success "BBR 已启用。"
        return 0
    fi

    if ask_yes_no "是否启用 BBR + FQ" "N"; then
        enable_bbr_fq
    else
        print_warning "跳过 BBR 设置。"
    fi
}

clean_system_junk() {
    print_separator
    print_info "清理系统垃圾。"
    print_separator

    if ! ask_yes_no "是否清理包缓存、无用依赖和临时文件" "Y"; then
        print_warning "跳过系统垃圾清理。"
        return 0
    fi

    case "$PKG_MANAGER" in
        apt)
            apt-get clean || true
            apt-get autoclean || true
            apt-get autoremove -y || true
            ;;
        dnf) dnf clean all || true; dnf autoremove -y || true ;;
        yum) yum clean all || true; yum autoremove -y || true ;;
        apk) rm -rf /var/cache/apk/* || true ;;
        zypper) zypper clean -a || true ;;
        pacman) pacman -Sc --noconfirm || true ;;
    esac

    print_info "清理 /tmp 和 /var/tmp 中 1 天以前的普通文件。"
    find /tmp /var/tmp -xdev -type f -mtime +1 -delete 2>/dev/null || true
    print_success "系统垃圾清理完成。"
}

clean_logs_menu() {
    print_separator
    printf "%b🗄️  请选择日志清理范围：%b\n" "$PURPLE" "$NC"
    printf "1) %b清理 7 天以前的 .log 文件%b\n" "$GREEN" "$NC"
    printf "2) %b清理 30 天以前的 .log 文件%b\n" "$GREEN" "$NC"
    printf "3) %b清理 180 天以前的 .log 文件%b\n" "$GREEN" "$NC"
    printf "4) %b清理所有 .log 文件%b\n" "$GREEN" "$NC"
    printf "5) %b不清理%b\n" "$YELLOW" "$NC"
    print_separator

    local choice mtime
    read -r -p "请输入选项 (1/2/3/4/5): " choice || choice="5"
    case "$choice" in
        1) mtime="+7" ;;
        2) mtime="+30" ;;
        3) mtime="+180" ;;
        4) mtime="all" ;;
        5) print_warning "跳过日志清理。"; return 0 ;;
        *) print_warning "无效选项，跳过日志清理。"; return 0 ;;
    esac

    print_warning "日志可能用于排查问题，清理前建议确认。"
    if ! ask_yes_no "确认执行日志清理" "N"; then
        print_warning "已取消日志清理。"
        return 0
    fi

    if [[ "$mtime" == "all" ]]; then
        find /var/log -type f -name '*.log' -delete 2>/dev/null || true
    else
        find /var/log -type f -name '*.log' -mtime "$mtime" -delete 2>/dev/null || true
    fi
    print_success "日志清理完成。"
}

final_report() {
    print_separator
    print_success "系统优化与安全增强流程完成。"
    print_separator

    printf "%b本次脚本包含并保留的功能：%b\n" "$WHITE" "$NC"
    printf "1) %b系统信息检测与系统更新。%b\n" "$GREEN" "$NC"
    printf "2) %b安装 sudo/wget/curl/OpenSSH/Fail2Ban/UFW 等常用组件。%b\n" "$GREEN" "$NC"
    printf "3) %bIPv4/IPv6 检测，并通过 /etc/gai.conf 设置解析优先级。%b\n" "$GREEN" "$NC"
    printf "4) %bSSH 服务检测、安装、端口修改、防火墙放行、防锁死校验。%b\n" "$GREEN" "$NC"
    printf "5) %b防火墙启用、SSH 端口保留、可选开放当前监听端口。%b\n" "$GREEN" "$NC"
    printf "6) %bFail2Ban SSH 防护启用。%b\n" "$GREEN" "$NC"
    printf "7) %bDNS、时区、SWAP、BBR+FQ 设置。%b\n" "$GREEN" "$NC"
    printf "8) %b系统垃圾与日志清理。%b\n" "$GREEN" "$NC"
    echo

    printf "%b📄 防火墙状态：%b\n" "$PURPLE" "$NC"
    show_firewall_status
    echo

    printf "%b🔒 Fail2Ban 状态：%b\n" "$PURPLE" "$NC"
    if command_exists fail2ban-client; then
        fail2ban-client status 2>/dev/null || true
    else
        print_warning "未安装 fail2ban-client。"
    fi
    echo

    printf "%b⚠️  重要提醒：%b如果修改了 SSH 端口，请先新开一个 SSH 窗口测试新端口能登录，再关闭当前窗口。%b\n" "$YELLOW" "$WHITE" "$NC"
    printf "%b日志文件：%b%s\n" "$WHITE" "$NC" "$LOG_FILE"
    printf "%b备份目录：%b%s\n" "$WHITE" "$NC" "$BACKUP_DIR"

    if [[ "$BBR_MODIFIED" == true ]]; then
        print_warning "BBR 设置已修改，建议重启后再次确认。"
        if ask_yes_no "是否现在重启系统" "N"; then
            reboot
        else
            print_warning "你选择稍后手动重启。"
        fi
    fi
}

main() {
    require_root
    init_log_and_backup
    get_system_info

    print_separator
    print_info "开始执行系统优化与安全增强脚本。"
    print_separator
    show_system_info

    if ask_yes_no "是否更新系统软件包" "Y"; then
        pkg_update
    else
        print_warning "跳过系统更新。"
    fi

    install_common_components
    check_and_set_network_priority
    configure_ssh_port
    ensure_firewall
    select_keep_ssh_port_and_close_others
    open_listening_service_ports
    setup_fail2ban
    manage_dns
    set_timezone_menu
    manage_swap
    manage_bbr
    clean_system_junk
    clean_logs_menu
    final_report
}

main "$@"
