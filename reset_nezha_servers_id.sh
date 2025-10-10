#!/bin/bash

# Nezha Dashboard Servers表ID重置工具
# 适用于Mac和Debian系统
# 使用方法: 
#   交互式: ./reset_nezha_servers_id.sh
#   参数式: ./reset_nezha_servers_id.sh [数据库文件路径]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认数据库文件路径
DEFAULT_DB_PATH="/opt/nezha/dashboard/data/sqlite.db"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "debian"
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

# 安装SQLite3
install_sqlite3() {
    local os=$(detect_os)
    
    case $os in
        "macos")
            print_info "检测到macOS系统，尝试使用Homebrew安装SQLite3..."
            if command -v brew &> /dev/null; then
                brew install sqlite
                print_success "SQLite3安装完成"
            else
                print_error "未找到Homebrew，请先安装Homebrew或手动安装SQLite3"
                exit 1
            fi
            ;;
        "debian")
            print_info "检测到Debian/Ubuntu系统，尝试使用apt安装SQLite3..."
            if command -v sudo &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y sqlite3
                print_success "SQLite3安装完成"
            else
                print_error "需要sudo权限来安装SQLite3，请手动安装: apt-get install sqlite3"
                exit 1
            fi
            ;;
        *)
            print_error "不支持的操作系统: $os"
            print_info "请手动安装SQLite3:"
            print_info "  macOS: brew install sqlite"
            print_info "  Debian/Ubuntu: sudo apt-get install sqlite3"
            exit 1
            ;;
    esac
}

# 检查并安装SQLite3
check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        print_warning "SQLite3未安装，尝试自动安装..."
        install_sqlite3
    else
        print_success "SQLite3已安装"
    fi
}

# 交互式选择数据库文件
interactive_db_selection() {
    print_info "请选择数据库文件路径:"
    echo "1) 使用默认路径: $DEFAULT_DB_PATH"
    echo "2) 手动输入路径"
    
    read -p "请选择 (1-2，直接回车使用默认路径): " choice
    
    case $choice in
        1|"")
            DB_FILE="$DEFAULT_DB_PATH"
            print_info "使用默认路径: $DEFAULT_DB_PATH"
            ;;
        2)
            read -p "请输入数据库文件完整路径: " DB_FILE
            ;;
        *)
            print_error "无效选择，使用默认路径"
            DB_FILE="$DEFAULT_DB_PATH"
            ;;
    esac
}

# 检查数据库文件
check_database_file() {
    if [ ! -f "$DB_FILE" ]; then
        print_error "数据库文件 '$DB_FILE' 不存在"
        print_info "请检查路径是否正确，或使用交互模式重新选择"
        exit 1
    fi
    
    # 检查文件是否可读
    if [ ! -r "$DB_FILE" ]; then
        print_error "数据库文件 '$DB_FILE' 不可读，请检查权限"
        exit 1
    fi
    
    print_success "数据库文件验证通过: $DB_FILE"
}

# 获取数据库文件所在目录
get_db_directory() {
    dirname "$DB_FILE"
}

# 检测Nezha运行方式
detect_nezha_mode() {
    local nz_base_path="/opt/nezha"
    local nz_dashboard_path="${nz_base_path}/dashboard"
    
    # 检测Docker方式
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_COMMAND="docker compose"
        if [ -f "$nz_dashboard_path/docker-compose.yaml" ]; then
            # 检查是否有nezha相关镜像（不需要sudo权限）
            if docker images --format "{{.Repository}}":"{{.Tag}}" 2>/dev/null | grep -w "nezhahq/nezha" >/dev/null 2>&1; then
                IS_DOCKER_NEZHA=1
                return
            fi
        fi
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_COMMAND="docker-compose"
        if [ -f "$nz_dashboard_path/docker-compose.yaml" ]; then
            # 检查是否有nezha相关镜像（不需要sudo权限）
            if docker images --format "{{.Repository}}":"{{.Tag}}" 2>/dev/null | grep -w "nezhahq/nezha" >/dev/null 2>&1; then
                IS_DOCKER_NEZHA=1
                return
            fi
        fi
    fi
    
    # 检测独立安装方式
    if [ -f "$nz_dashboard_path/app" ]; then
        IS_DOCKER_NEZHA=0
        return
    fi
    
    # 如果都检测不到，默认为独立安装
    IS_DOCKER_NEZHA=0
}

# 检测系统初始化方式
detect_init_system() {
    local init=$(readlink /sbin/init 2>/dev/null)
    case "$init" in
        *systemd*)
            INIT=systemd
            ;;
        *openrc-init*|*busybox*)
            INIT=openrc
            ;;
        *)
            INIT=systemd  # 默认使用systemd
            ;;
    esac
}

# 重启Nezha Dashboard
restart_nezha_dashboard() {
    print_info "正在重启Nezha Dashboard..."
    
    if [ "$IS_DOCKER_NEZHA" = 1 ]; then
        restart_nezha_docker
    else
        restart_nezha_standalone
    fi
}

# Docker方式重启
restart_nezha_docker() {
    print_info "使用Docker方式重启..."
    if [ -n "$DOCKER_COMPOSE_COMMAND" ]; then
        sudo $DOCKER_COMPOSE_COMMAND -f /opt/nezha/dashboard/docker-compose.yaml down
        sleep 2
        sudo $DOCKER_COMPOSE_COMMAND -f /opt/nezha/dashboard/docker-compose.yaml up -d
        print_success "Docker方式重启完成"
    else
        print_error "Docker Compose命令不可用"
        return 1
    fi
}

# 独立安装方式重启
restart_nezha_standalone() {
    print_info "使用独立安装方式重启..."
    
    if [ "$INIT" = "systemd" ]; then
        sudo systemctl daemon-reload
        sudo systemctl restart nezha-dashboard
        print_success "systemd方式重启完成"
    elif [ "$INIT" = "openrc" ]; then
        sudo rc-service nezha-dashboard restart
        print_success "openrc方式重启完成"
    else
        print_warning "未知的初始化系统，尝试使用systemd"
        sudo systemctl daemon-reload
        sudo systemctl restart nezha-dashboard
        print_success "systemd方式重启完成"
    fi
}

# 主函数
main() {
    print_info "=== Nezha Dashboard Servers表ID重置工具 ==="
    print_info "支持系统: macOS, Debian/Ubuntu"
    echo
    
    # 检查SQLite3
    check_sqlite3
    echo
    
    # 检测Nezha运行方式
    print_info "检测Nezha运行方式..."
    detect_nezha_mode
    detect_init_system
    
    if [ "$IS_DOCKER_NEZHA" = 1 ]; then
        print_success "检测到Docker方式运行的Nezha"
    else
        print_success "检测到独立安装方式运行的Nezha"
    fi
    echo
    
    # 确定数据库文件路径
    if [ $# -eq 0 ]; then
        # 直接使用默认路径
        DB_FILE="$DEFAULT_DB_PATH"
        print_info "使用默认数据库文件: $DB_FILE"
        print_info "如需选择其他路径，请使用: $0 interactive"
    elif [ "$1" = "interactive" ]; then
        # 交互模式
        print_info "进入交互模式..."
        interactive_db_selection
    else
        # 参数模式
        DB_FILE="$1"
        print_info "使用参数指定的数据库文件: $DB_FILE"
    fi
    
    # 检查数据库文件
    check_database_file
    echo
    
    # 获取数据库所在目录
    DB_DIR=$(get_db_directory)
    print_info "数据库所在目录: $DB_DIR"
    
    # 检查servers表是否存在
    if ! sqlite3 "$DB_FILE" "SELECT name FROM sqlite_master WHERE type='table' AND name='servers';" | grep -q "servers"; then
        print_error "数据库中没有找到servers表"
        exit 1
    fi
    
    # 检查servers表是否有数据
    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM servers;")
    if [ "$count" -eq 0 ]; then
        print_warning "servers表为空，无需重置"
        exit 0
    fi
    
    print_info "servers表中有 $count 条记录"
    echo
    
    # 显示重置前的数据
    print_info "重置前的数据:"
    sqlite3 "$DB_FILE" "SELECT id, name, uuid FROM servers ORDER BY id;"
    echo
    
    # 确认操作
    read -p "确认要重置servers表的ID吗？这将重新排序所有记录的ID (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
    
    # 备份当前数据
    local backup_file="$DB_DIR/backup_$(date +%Y%m%d_%H%M%S).db"
    print_info "正在备份当前数据到: $backup_file"
    sqlite3 "$DB_FILE" ".backup $backup_file"
    print_success "备份完成"
    echo
    
    # 1. 重置AUTOINCREMENT计数器
    print_info "正在重置AUTOINCREMENT计数器..."
    sqlite3 "$DB_FILE" "DELETE FROM sqlite_sequence WHERE name='servers';"
    
    # 2. 重新排序现有记录的ID
    print_info "正在重新排序ID..."
    sqlite3 "$DB_FILE" "
    UPDATE servers 
    SET id = (
        SELECT COUNT(*) 
        FROM servers s2 
        WHERE s2.rowid <= servers.rowid
    );"
    
    # 3. 更新sqlite_sequence表
    print_info "正在更新AUTOINCREMENT计数器..."
    sqlite3 "$DB_FILE" "
    INSERT INTO sqlite_sequence (name, seq) 
    VALUES ('servers', (SELECT MAX(id) FROM servers));"
    
    # 显示重置后的数据
    print_success "重置完成！"
    echo
    print_info "重置后的数据:"
    sqlite3 "$DB_FILE" "SELECT id, name, uuid FROM servers ORDER BY id;"
    echo
    
    # 验证sqlite_sequence
    print_info "当前AUTOINCREMENT计数器:"
    sqlite3 "$DB_FILE" "SELECT * FROM sqlite_sequence WHERE name='servers';"
    echo
    
    local next_id=$(sqlite3 "$DB_FILE" "SELECT seq FROM sqlite_sequence WHERE name='servers';")
    print_success "✅ servers表ID重置完成！"
    print_info "备份文件: $backup_file"
    print_info "下次插入新记录时，ID将从 $((next_id + 1)) 开始"
    echo
    
    # 重启Nezha Dashboard
    print_info "正在重启Nezha Dashboard以使更改生效..."
    if restart_nezha_dashboard; then
        print_success "Nezha Dashboard重启成功！"
    else
        print_warning "Nezha Dashboard重启失败，请手动重启"
    fi
}

# 显示帮助信息
show_help() {
    echo "Nezha Dashboard Servers表ID重置工具"
    echo
    echo "使用方法:"
    echo "  $0                    # 使用默认路径直接运行"
    echo "  $0 interactive        # 交互模式选择数据库路径"
    echo "  $0 <数据库文件路径>    # 指定数据库文件路径"
    echo "  $0 -h, --help         # 显示帮助信息"
    echo
    echo "功能:"
    echo "  - 自动检测操作系统并安装SQLite3依赖"
    echo "  - 自动检测Nezha运行方式(Docker/独立安装)"
    echo "  - 交互式或参数式选择数据库文件"
    echo "  - 自动备份数据库文件"
    echo "  - 重置Nezha Dashboard中servers表的ID从1开始重新排序"
    echo "  - 自动重启Nezha Dashboard使更改生效"
    echo "  - 支持macOS (Homebrew) 和 Debian/Ubuntu (apt)"
    echo
    echo "默认数据库路径: $DEFAULT_DB_PATH"
}

# 只有在直接执行脚本时才运行main函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 处理命令行参数
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            main "$@"
            ;;
    esac
fi
