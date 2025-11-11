#!/bin/bash

# Mosdns-x 自动化管理脚本
# 功能：安装、更新、配置、守护进程管理
# 作者：Lide iBytebox
# 版本：v2.0

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
MOSDNS_VERSION=""
MOSDNS_BINARY="/usr/local/bin/mosdns-x"
MOSDNS_CONFIG_DIR="/etc/mosdns-x"
MOSDNS_CONFIG_FILE="/etc/mosdns-x/config.yaml"
MOSDNS_LOG_DIR="/var/log/mosdns-x"
MOSDNS_LOG_FILE="/var/log/mosdns-x/mosdns-x.log"
MOSDNS_SERVICE_FILE="/etc/systemd/system/mosdns.service"
MOSDNS_LOGROTATE_FILE="/etc/logrotate.d/mosdns-x"
MOSDNS_USER="mosdns"
MOSDNS_GROUP="mosdns"
RESOLV_CONF_BACKUP="/etc/resolv.conf.mosdns-backup"

# GitHub 配置
GITHUB_REPO="pmkol/mosdns-x"
GITHUB_API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
GITHUB_RELEASES_URL="https://github.com/${GITHUB_REPO}/releases"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统架构
get_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l) echo "arm" ;;
        *) echo "unsupported" ;;
    esac
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_error "请使用: sudo $0 $@"
        exit 1
    fi
}

# 检查权限和端口可用性
check_permissions() {
    log_info "检查权限和端口可用性..."
    
    # 检查端口53是否被占用
    if ss -tuln | grep -q ":53 "; then
        local port_process=$(ss -tuln | grep ":53 " | head -1)
        log_warning "端口53已被占用: $port_process"
        log_warning "Mosdns-x需要端口53，请确保没有其他DNS服务运行"
        
        # 询问是否继续
        read -p "是否继续安装? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "安装已取消"
            exit 0
        fi
    fi
    
    # 检查是否有权限访问端口53
    if ! ss -tuln | grep -q ":53 " && ! timeout 1 bash -c "</dev/tcp/127.0.0.1/53" 2>/dev/null; then
        log_info "端口53可用"
    fi
    
    log_success "权限检查完成"
}

# 检查系统依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    local missing_deps=()
    
    # 检查必需的命令
    for cmd in curl wget unzip systemctl dnsutils; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "安装缺失的依赖: ${missing_deps[*]}"
        apt-get update
        apt-get install -y ${missing_deps[@]}
    fi
    
    log_success "系统依赖检查完成"
}

# 获取最新版本
get_latest_version() {
    # 尝试从GitHub API获取
    local version=$(curl -s "$GITHUB_API_URL" | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$' 2>/dev/null || echo "")
    
    if [[ -z "$version" ]]; then
        # 备用方案：解析releases页面
        version=$(curl -s "$GITHUB_RELEASES_URL" | grep -o 'tag/[^"]*' | head -1 | cut -d'/' -f2 2>/dev/null || echo "")
    fi
    
    if [[ -z "$version" ]]; then
        version="v25.10.08"
    fi
    
    echo "$version"
}

# 检查当前版本
get_current_version() {
    if [[ -f "$MOSDNS_BINARY" ]]; then
        $MOSDNS_BINARY version 2>/dev/null | grep -o 'v[0-9.]*' | head -1 || echo "unknown"
    else
        echo "not_installed"
    fi
}

# 下载并安装Mosdns-x
install_mosdns_x() {
    local version=$1
    local arch=$(get_architecture)
    
    if [[ "$arch" == "unsupported" ]]; then
        log_error "不支持的架构: $(uname -m)"
        exit 1
    fi
    
    log_info "下载 Mosdns-x $version (架构: $arch)..."
    
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/mosdns-linux-${arch}.zip"
    local temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/mosdns-linux-${arch}.zip"
    
    # 下载文件
    if ! wget -q --show-progress -O "$zip_file" "$download_url"; then
        log_error "下载失败: $download_url"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # 解压并安装
    log_info "解压并安装..."
    cd "$temp_dir"
    unzip -q "$zip_file"
    
    # 安装二进制文件
    install -m 755 mosdns "$MOSDNS_BINARY"
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    log_success "Mosdns-x $version 安装完成"
}

# 创建用户和目录
setup_user_and_dirs() {
    log_info "创建用户和目录..."
    
    # 创建配置目录
    mkdir -p "$MOSDNS_CONFIG_DIR"
    mkdir -p "$MOSDNS_LOG_DIR"
    
    # 检查是否为root用户运行
    if [[ $EUID -eq 0 ]]; then
        # root用户运行，创建专用用户但服务以root运行
        if ! id "$MOSDNS_USER" &>/dev/null; then
            useradd -r -s /bin/false -d "$MOSDNS_CONFIG_DIR" "$MOSDNS_USER"
            log_info "创建用户: $MOSDNS_USER（用于文件权限管理）"
        fi
        
        # 设置目录权限（root拥有，mosdns用户可读）
        chown -R root:root "$MOSDNS_CONFIG_DIR"
        chown -R root:root "$MOSDNS_LOG_DIR"
        chmod 755 "$MOSDNS_CONFIG_DIR"
        chmod 755 "$MOSDNS_LOG_DIR"
        
        log_info "使用root权限运行，目录权限已优化"
    else
        # 非root用户运行，使用专用用户
        if ! id "$MOSDNS_USER" &>/dev/null; then
            useradd -r -s /bin/false -d "$MOSDNS_CONFIG_DIR" "$MOSDNS_USER"
            log_info "创建用户: $MOSDNS_USER"
        fi
        
        # 设置权限
        chown -R "$MOSDNS_USER:$MOSDNS_GROUP" "$MOSDNS_CONFIG_DIR"
        chown -R "$MOSDNS_USER:$MOSDNS_GROUP" "$MOSDNS_LOG_DIR"
        
        log_warning "非root用户运行，可能需要额外权限配置"
    fi
    
    log_success "用户和目录设置完成"
}

# 创建配置文件
create_config() {
    log_info "创建配置文件..."
    
    cat > "$MOSDNS_CONFIG_FILE" << 'EOF'
# mosdns-x 并发查询（无分流）配置

log:
  level: info
  file: /var/log/mosdns-x/mosdns-x.log

plugins:
  # 缓存插件
  - tag: cache
    type: cache
    args:
      size: 1024
      lazy_cache_ttl: 1800

  # 并发上游：取最先返回的可用答案
  - tag: forward_all
    type: fast_forward
    args:
      upstream:
        # 阿里
        - addr: "udp://223.5.5.5"
        - addr: "tls://dns.alidns.com"

        # DNSPod / doh.pub
        - addr: "udp://119.29.29.29"
        - addr: "tls://dot.pub"

        # Cloudflare
        - addr: "udp://1.1.1.1"
        - addr: "tls://cloudflare-dns.com"

        # Google
        - addr: "udp://8.8.8.8"
        - addr: "tls://dns.google"

  # 主流水线：小缓存 → 并发优选
  - tag: main
    type: sequence
    args:
      exec:
        - cache
        - forward_all

# 监听（双栈 UDP/TCP 53）
servers:
  - exec: main
    listeners:
      - addr: :53
        protocol: udp
      - addr: :53
        protocol: tcp
EOF

    # 设置权限
    if [[ $EUID -eq 0 ]]; then
        # root用户运行，文件归root所有
        chown root:root "$MOSDNS_CONFIG_FILE"
    else
        # 非root用户运行，文件归mosdns用户所有
        chown "$MOSDNS_USER:$MOSDNS_GROUP" "$MOSDNS_CONFIG_FILE"
    fi
    chmod 644 "$MOSDNS_CONFIG_FILE"
    
    log_success "配置文件创建完成"
}

# 创建systemd服务
create_systemd_service() {
    log_info "创建systemd服务..."
    
    # 检查是否为root用户运行
    if [[ $EUID -eq 0 ]]; then
        # root用户运行，使用root权限以访问端口53
        cat > "$MOSDNS_SERVICE_FILE" << EOF
[Unit]
Description=A DNS forwarder
Documentation=https://github.com/pmkol/mosdns-x
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$MOSDNS_BINARY start --as-service -d /usr/local/bin -c $MOSDNS_CONFIG_FILE
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mosdns

# 安全设置（root用户运行时的安全配置）
NoNewPrivileges=false
PrivateTmp=true
ProtectSystem=false
ProtectHome=false
ReadWritePaths=$MOSDNS_LOG_DIR $MOSDNS_CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF
        log_info "使用root权限运行服务（需要访问端口53）"
    else
        # 非root用户运行，使用专用用户
        cat > "$MOSDNS_SERVICE_FILE" << EOF
[Unit]
Description=A DNS forwarder
Documentation=https://github.com/pmkol/mosdns-x
After=network.target

[Service]
Type=simple
User=$MOSDNS_USER
Group=$MOSDNS_GROUP
ExecStart=$MOSDNS_BINARY start --as-service -d /usr/local/bin -c $MOSDNS_CONFIG_FILE
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mosdns

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$MOSDNS_LOG_DIR

[Install]
WantedBy=multi-user.target
EOF
        log_warning "非root用户运行，可能需要额外配置才能访问端口53"
    fi

    # 重新加载systemd
    systemctl daemon-reload
    
    log_success "systemd服务创建完成"
}

# 创建日志轮转配置
create_logrotate() {
    log_info "创建日志轮转配置..."
    
    # 根据运行用户设置日志轮转权限
    if [[ $EUID -eq 0 ]]; then
        # root用户运行
        cat > "$MOSDNS_LOGROTATE_FILE" << EOF
$MOSDNS_LOG_FILE {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload mosdns > /dev/null 2>&1 || true
    endscript
}
EOF
    else
        # 非root用户运行
        cat > "$MOSDNS_LOGROTATE_FILE" << EOF
$MOSDNS_LOG_FILE {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 $MOSDNS_USER $MOSDNS_GROUP
    postrotate
        systemctl reload mosdns > /dev/null 2>&1 || true
    endscript
}
EOF
    fi

    log_success "日志轮转配置创建完成"
}

# 配置系统DNS
configure_system_dns() {
    log_info "配置系统DNS..."
    
    # 备份原始resolv.conf
    if [[ -f "/etc/resolv.conf" && ! -f "$RESOLV_CONF_BACKUP" ]]; then
        cp /etc/resolv.conf "$RESOLV_CONF_BACKUP"
        log_info "已备份原始DNS配置到: $RESOLV_CONF_BACKUP"
    fi
    
    # 检查是否已经配置了mosdns
    if grep -q "nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null; then
        log_info "系统DNS已配置为使用Mosdns-x"
        return 0
    fi
    
    # 移除chattr保护（如果存在）
    if [[ -f "/etc/resolv.conf" ]]; then
        chattr -i /etc/resolv.conf 2>/dev/null || true
    fi
    
    # 配置DNS为127.0.0.1
    echo -e "nameserver 127.0.0.1\n" > /etc/resolv.conf
    
    # 添加保护，防止被其他程序修改
    chattr +i /etc/resolv.conf
    
    log_success "系统DNS已配置为使用Mosdns-x (127.0.0.1)"
}

# 恢复系统DNS
restore_system_dns() {
    log_info "恢复系统DNS配置..."
    
    # 移除chattr保护
    if [[ -f "/etc/resolv.conf" ]]; then
        chattr -i /etc/resolv.conf 2>/dev/null || true
    fi
    
    # 恢复原始配置
    if [[ -f "$RESOLV_CONF_BACKUP" ]]; then
        cp "$RESOLV_CONF_BACKUP" /etc/resolv.conf
        rm -f "$RESOLV_CONF_BACKUP"
        log_success "已恢复原始DNS配置"
    else
        # 如果没有备份，使用默认配置
        cat > /etc/resolv.conf << EOF
# Generated by NetworkManager
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
        log_success "已设置默认DNS配置"
    fi
}

# 启动并启用服务
start_service() {
    log_info "启动并启用服务..."
    
    # 启动服务
    systemctl start mosdns
    
    # 启用开机自启动
    systemctl enable mosdns
    
    # 等待服务启动
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet mosdns; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        systemctl status mosdns
        exit 1
    fi
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    # 检查二进制文件
    if [[ ! -f "$MOSDNS_BINARY" ]]; then
        log_error "二进制文件不存在: $MOSDNS_BINARY"
        return 1
    fi
    
    # 检查配置文件
    if [[ ! -f "$MOSDNS_CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $MOSDNS_CONFIG_FILE"
        return 1
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet mosdns; then
        log_error "服务未运行"
        return 1
    fi
    
    # 检查端口监听
    if ! ss -tuln | grep -q ":53 "; then
        log_error "端口53未监听"
        return 1
    fi
    
    # 测试DNS解析
    if ! nslookup google.com 127.0.0.1 >/dev/null 2>&1; then
        log_error "DNS解析测试失败"
        return 1
    fi
    
    log_success "安装验证通过"
    return 0
}

# 显示状态信息
show_status() {
    local current_version=$(get_current_version)
    local service_status=$(systemctl is-active mosdns 2>/dev/null || echo "inactive")
    local port_status=$(ss -tuln | grep -q ":53 " && echo "listening" || echo "not_listening")
    
    echo
    log_info "=== Mosdns-x 状态信息 ==="
    echo "版本: $current_version"
    echo "服务状态: $service_status"
    echo "端口状态: $port_status"
    echo "配置文件: $MOSDNS_CONFIG_FILE"
    echo "日志文件: $MOSDNS_LOG_FILE"
    echo
}

# 更新Mosdns-x
update_mosdns_x() {
    local latest_version=$(get_latest_version)
    local current_version=$(get_current_version)
    
    if [[ "$current_version" == "not_installed" ]]; then
        log_error "Mosdns-x 未安装，请先运行安装"
        exit 1
    fi
    
    if [[ "$current_version" == "$latest_version" ]]; then
        log_info "已是最新版本: $current_version"
        return 0
    fi
    
    log_info "更新 Mosdns-x: $current_version -> $latest_version"
    
    # 停止服务
    systemctl stop mosdns
    
    # 安装新版本
    install_mosdns_x "$latest_version"
    
    # 启动服务
    systemctl start mosdns
    
    log_success "更新完成"
}

# 卸载Mosdns-x
uninstall_mosdns_x() {
    log_info "卸载 Mosdns-x..."
    
    # 停止并禁用服务
    systemctl stop mosdns 2>/dev/null || true
    systemctl disable mosdns 2>/dev/null || true
    
    # 恢复系统DNS配置
    restore_system_dns
    
    # 删除文件
    rm -f "$MOSDNS_BINARY"
    rm -f "$MOSDNS_SERVICE_FILE"
    rm -f "$MOSDNS_LOGROTATE_FILE"
    
    # 删除目录（可选）
    read -p "是否删除配置目录和日志目录? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$MOSDNS_CONFIG_DIR"
        rm -rf "$MOSDNS_LOG_DIR"
        userdel "$MOSDNS_USER" 2>/dev/null || true
    fi
    
    # 重新加载systemd
    systemctl daemon-reload
    
    log_success "卸载完成"
}

# 显示帮助信息
show_help() {
    cat << EOF
Mosdns-x 自动化管理脚本 v2.0

用法: $0 [命令]

命令:
  install     安装 Mosdns-x
  update      更新到最新版本
  uninstall   卸载 Mosdns-x
  status      显示状态信息
  restart     重启服务
  stop        停止服务
  start       启动服务
  logs        查看日志
  test        测试DNS解析
  dns-config  配置系统DNS
  dns-restore 恢复系统DNS
  help        显示此帮助信息

示例:
  $0 install    # 安装 Mosdns-x
  $0 status     # 查看状态
  $0 test       # 测试DNS解析
  $0 update     # 更新到最新版本

EOF
}

# 测试DNS解析
test_dns() {
    log_info "测试DNS解析..."
    
    local test_domains=("google.com" "baidu.com" "github.com" "cloudflare.com")
    
    for domain in "${test_domains[@]}"; do
        echo -n "测试 $domain: "
        if time nslookup "$domain" 127.0.0.1 >/dev/null 2>&1; then
            echo -e "${GREEN}成功${NC}"
        else
            echo -e "${RED}失败${NC}"
        fi
    done
}

# 查看日志
show_logs() {
    log_info "显示最近的日志..."
    journalctl -u mosdns -n 20 --no-pager
}

# 主函数
main() {
    check_root
    
    case "${1:-install}" in
        install)
            log_info "开始安装 Mosdns-x..."
            check_dependencies
            check_permissions
            setup_user_and_dirs
            local latest_version=$(get_latest_version)
        install_mosdns_x "$latest_version"
            create_config
            create_systemd_service
            create_logrotate
            start_service
            configure_system_dns
            verify_installation
            show_status
            log_success "安装完成！"
            ;;
        update)
            update_mosdns_x
            show_status
            ;;
        uninstall)
            uninstall_mosdns_x
            ;;
        status)
            show_status
            ;;
        restart)
            systemctl restart mosdns
            log_success "服务已重启"
            ;;
        stop)
            systemctl stop mosdns
            log_success "服务已停止"
            ;;
        start)
            systemctl start mosdns
            log_success "服务已启动"
            ;;
        logs)
            show_logs
            ;;
        test)
            test_dns
            ;;
        dns-config)
            configure_system_dns
            ;;
        dns-restore)
            restore_system_dns
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
