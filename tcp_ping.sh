#!/bin/bash

# TCP Ping 服务器管理脚本
# 支持服务端安装/卸载/管理 和 客户端测试
# 作者: Lide
# 版本: 1.0

set -e

# 配置变量
SCRIPT_DIR="/opt/tcp-ping"
SERVICE_NAME="tcp-ping"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DEFAULT_PORT=9966
DEFAULT_HOST="0.0.0.0"
PYTHON_SCRIPT="tcp_ping_server.py"
CLIENT_SCRIPT="tcp_ping_client.py"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查并安装依赖
check_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查Python3
    if ! command -v python3 &> /dev/null; then
        log_warn "Python3 未安装，正在安装..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y python3
        elif command -v yum &> /dev/null; then
            yum install -y python3
        elif command -v dnf &> /dev/null; then
            dnf install -y python3
        else
            log_error "无法自动安装Python3，请手动安装"
            exit 1
        fi
    else
        log_info "Python3 已安装: $(python3 --version)"
    fi
    
    # 检查systemd
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd 未安装，此脚本需要systemd支持"
        exit 1
    fi
    
    # 检查网络工具
    if ! command -v ss &> /dev/null; then
        log_warn "ss 命令未找到，正在安装 iproute2..."
        if command -v apt-get &> /dev/null; then
            apt-get install -y iproute2
        elif command -v yum &> /dev/null; then
            yum install -y iproute
        fi
    fi
    
    log_info "依赖检查完成"
}

# 创建服务端Python脚本
create_server_script() {
    log_info "创建服务端脚本..."
    cat > "${SCRIPT_DIR}/${PYTHON_SCRIPT}" << 'EOF'
#!/usr/bin/env python3
"""
TCP Ping Echo Server
用于测试TCP连接延迟的服务器
支持多种测试模式：echo、timestamp、ping
"""

import socket
import threading
import time
import json
import signal
import sys
from datetime import datetime
import argparse

class TCPPingServer:
    def __init__(self, host='0.0.0.0', port=9966):
        self.host = host
        self.port = port
        self.running = True
        self.stats = {
            'connections': 0,
            'packets': 0,
            'start_time': time.time()
        }
        
    def handle_client(self, client_socket, client_address):
        """处理客户端连接"""
        self.stats['connections'] += 1
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 新连接: {client_address}")
        
        try:
            while self.running:
                # 接收数据
                data = client_socket.recv(1024)
                if not data:
                    break
                    
                self.stats['packets'] += 1
                received_time = time.time()
                
                # 解析请求类型
                try:
                    request = json.loads(data.decode('utf-8'))
                    request_type = request.get('type', 'echo')
                except:
                    # 如果不是JSON格式，当作简单echo处理
                    request_type = 'echo'
                    request = {'data': data.decode('utf-8', errors='ignore')}
                
                # 根据请求类型处理
                if request_type == 'ping':
                    # Ping模式：返回时间戳
                    response = {
                        'type': 'pong',
                        'server_time': received_time,
                        'client_time': request.get('client_time', 0),
                        'timestamp': datetime.now().isoformat()
                    }
                elif request_type == 'timestamp':
                    # 时间戳模式：返回服务器时间
                    response = {
                        'type': 'timestamp',
                        'server_time': received_time,
                        'timestamp': datetime.now().isoformat(),
                        'data': request.get('data', '')
                    }
                else:
                    # Echo模式：原样返回
                    response = {
                        'type': 'echo',
                        'data': request.get('data', data.decode('utf-8', errors='ignore')),
                        'server_time': received_time,
                        'timestamp': datetime.now().isoformat()
                    }
                
                # 发送响应
                response_data = json.dumps(response, ensure_ascii=False).encode('utf-8')
                client_socket.send(response_data)
                
        except Exception as e:
            print(f"处理客户端 {client_address} 时出错: {e}")
        finally:
            client_socket.close()
            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] 连接关闭: {client_address}")
    
    def start(self):
        """启动服务器"""
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        
        try:
            server_socket.bind((self.host, self.port))
            server_socket.listen(5)
            print(f"TCP Ping服务器启动成功")
            print(f"监听地址: {self.host}:{self.port}")
            print(f"支持的模式: echo, ping, timestamp")
            print("按 Ctrl+C 停止服务器")
            print("-" * 50)
            
            while self.running:
                try:
                    client_socket, client_address = server_socket.accept()
                    client_thread = threading.Thread(
                        target=self.handle_client,
                        args=(client_socket, client_address)
                    )
                    client_thread.daemon = True
                    client_thread.start()
                except socket.error:
                    if self.running:
                        print("接受连接时出错")
                    break
                    
        except Exception as e:
            print(f"服务器启动失败: {e}")
        finally:
            server_socket.close()
            self.print_stats()
    
    def stop(self):
        """停止服务器"""
        print("\n正在停止服务器...")
        self.running = False
    
    def print_stats(self):
        """打印统计信息"""
        uptime = time.time() - self.stats['start_time']
        print(f"\n服务器统计信息:")
        print(f"运行时间: {uptime:.2f} 秒")
        print(f"总连接数: {self.stats['connections']}")
        print(f"总数据包: {self.stats['packets']}")

def signal_handler(sig, frame):
    """信号处理器"""
    print(f"\n收到信号 {sig}，正在关闭服务器...")
    server.stop()
    sys.exit(0)

def main():
    parser = argparse.ArgumentParser(description='TCP Ping Echo Server')
    parser.add_argument('--host', default='0.0.0.0', help='监听地址 (默认: 0.0.0.0)')
    parser.add_argument('--port', type=int, default=9966, help='监听端口 (默认: 9966)')
    args = parser.parse_args()
    
    global server
    server = TCPPingServer(args.host, args.port)
    
    # 注册信号处理器
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()

if __name__ == '__main__':
    main()
EOF
    chmod +x "${SCRIPT_DIR}/${PYTHON_SCRIPT}"
    log_info "服务端脚本创建完成"
}

# 创建客户端Python脚本
create_client_script() {
    log_info "创建客户端脚本..."
    cat > "${SCRIPT_DIR}/${CLIENT_SCRIPT}" << 'EOF'
#!/usr/bin/env python3
"""
TCP Ping Client
用于测试TCP连接延迟的客户端工具
"""

import socket
import time
import json
import argparse
import statistics
from datetime import datetime

class TCPPingClient:
    def __init__(self, host, port, timeout=5):
        self.host = host
        self.port = port
        self.timeout = timeout
    
    def ping_once(self, request_type='ping', data=''):
        """执行一次ping测试"""
        try:
            # 创建socket连接
            start_time = time.time()
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            
            # 连接服务器
            connect_start = time.time()
            sock.connect((self.host, self.port))
            connect_time = time.time() - connect_start
            
            # 准备请求数据
            request = {
                'type': request_type,
                'client_time': time.time(),
                'data': data
            }
            
            # 发送数据
            send_start = time.time()
            request_data = json.dumps(request).encode('utf-8')
            sock.send(request_data)
            
            # 接收响应
            response_data = sock.recv(1024)
            receive_time = time.time()
            
            # 解析响应
            response = json.loads(response_data.decode('utf-8'))
            server_time = response.get('server_time', 0)
            
            # 计算延迟
            total_time = receive_time - send_start
            rtt = total_time * 1000  # 转换为毫秒
            
            sock.close()
            
            return {
                'success': True,
                'connect_time': connect_time * 1000,
                'rtt': rtt,
                'server_time': server_time,
                'timestamp': response.get('timestamp', ''),
                'response': response
            }
            
        except Exception as e:
            return {
                'success': False,
                'error': str(e),
                'rtt': None
            }
    
    def ping_multiple(self, count=10, interval=1, request_type='ping', data=''):
        """执行多次ping测试"""
        results = []
        print(f"正在测试 {self.host}:{self.port} ...")
        print(f"请求类型: {request_type}")
        print(f"测试次数: {count}, 间隔: {interval}秒")
        print("-" * 60)
        
        for i in range(count):
            result = self.ping_once(request_type, data)
            results.append(result)
            
            if result['success']:
                print(f"第{i+1:2d}次: 延迟 {result['rtt']:6.2f}ms (连接: {result['connect_time']:6.2f}ms)")
            else:
                print(f"第{i+1:2d}次: 失败 - {result['error']}")
            
            if i < count - 1:  # 最后一次不需要等待
                time.sleep(interval)
        
        # 统计结果
        successful_results = [r for r in results if r['success']]
        if successful_results:
            rtts = [r['rtt'] for r in successful_results]
            connect_times = [r['connect_time'] for r in successful_results]
            
            print("-" * 60)
            print(f"统计结果:")
            print(f"成功: {len(successful_results)}/{count}")
            print(f"RTT - 最小: {min(rtts):.2f}ms, 最大: {max(rtts):.2f}ms, 平均: {statistics.mean(rtts):.2f}ms")
            print(f"连接时间 - 最小: {min(connect_times):.2f}ms, 最大: {max(connect_times):.2f}ms, 平均: {statistics.mean(connect_times):.2f}ms")
            
            if len(rtts) > 1:
                print(f"RTT标准差: {statistics.stdev(rtts):.2f}ms")
        else:
            print("所有测试都失败了")
        
        return results

def main():
    parser = argparse.ArgumentParser(description='TCP Ping Client')
    parser.add_argument('host', help='目标主机地址')
    parser.add_argument('port', type=int, help='目标端口')
    parser.add_argument('-c', '--count', type=int, default=10, help='测试次数 (默认: 10)')
    parser.add_argument('-i', '--interval', type=float, default=1, help='测试间隔秒数 (默认: 1)')
    parser.add_argument('-t', '--timeout', type=int, default=5, help='连接超时秒数 (默认: 5)')
    parser.add_argument('--type', choices=['ping', 'echo', 'timestamp'], default='ping', help='请求类型 (默认: ping)')
    parser.add_argument('--data', default='', help='发送的数据 (echo模式使用)')
    
    args = parser.parse_args()
    
    client = TCPPingClient(args.host, args.port, args.timeout)
    client.ping_multiple(args.count, args.interval, args.type, args.data)

if __name__ == '__main__':
    main()
EOF
    chmod +x "${SCRIPT_DIR}/${CLIENT_SCRIPT}"
    log_info "客户端脚本创建完成"
}

# 创建systemd服务文件
create_service_file() {
    local host=$1
    local port=$2
    
    log_info "创建systemd服务文件..."
    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=TCP Ping Echo Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${SCRIPT_DIR}
ExecStart=/usr/bin/python3 ${SCRIPT_DIR}/${PYTHON_SCRIPT} --host ${host} --port ${port}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    log_info "服务文件创建完成"
}

# 安装服务端
install_server() {
    local host=${1:-$DEFAULT_HOST}
    local port=${2:-$DEFAULT_PORT}
    
    log_info "开始安装TCP Ping服务器..."
    log_info "监听地址: ${host}:${port}"
    
    # 检查依赖
    check_dependencies
    
    # 创建目录
    mkdir -p "${SCRIPT_DIR}"
    
    # 创建脚本
    create_server_script
    create_client_script
    
    # 创建服务文件
    create_service_file "$host" "$port"
    
    # 重载systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable "${SERVICE_NAME}.service"
    
    # 启动服务
    systemctl start "${SERVICE_NAME}.service"
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log_info "TCP Ping服务器安装成功！"
        log_info "服务状态: $(systemctl is-active ${SERVICE_NAME}.service)"
        log_info "监听端口: ${port}"
        log_info "服务管理命令:"
        log_info "  启动: systemctl start ${SERVICE_NAME}"
        log_info "  停止: systemctl stop ${SERVICE_NAME}"
        log_info "  重启: systemctl restart ${SERVICE_NAME}"
        log_info "  状态: systemctl status ${SERVICE_NAME}"
        log_info "  日志: journalctl -u ${SERVICE_NAME} -f"
    else
        log_error "服务启动失败，请检查日志: journalctl -u ${SERVICE_NAME}"
        exit 1
    fi
}

# 卸载服务端
uninstall_server() {
    log_info "开始卸载TCP Ping服务器..."
    
    # 停止服务
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log_info "停止服务..."
        systemctl stop "${SERVICE_NAME}.service"
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet "${SERVICE_NAME}.service"; then
        log_info "禁用服务..."
        systemctl disable "${SERVICE_NAME}.service"
    fi
    
    # 删除服务文件
    if [[ -f "${SERVICE_FILE}" ]]; then
        log_info "删除服务文件..."
        rm -f "${SERVICE_FILE}"
    fi
    
    # 删除脚本目录
    if [[ -d "${SCRIPT_DIR}" ]]; then
        log_info "删除脚本目录..."
        rm -rf "${SCRIPT_DIR}"
    fi
    
    # 重载systemd
    systemctl daemon-reload
    
    log_info "TCP Ping服务器卸载完成！"
}

# 服务管理
manage_service() {
    local action=$1
    
    case $action in
        start)
            log_info "启动TCP Ping服务..."
            systemctl start "${SERVICE_NAME}.service"
            ;;
        stop)
            log_info "停止TCP Ping服务..."
            systemctl stop "${SERVICE_NAME}.service"
            ;;
        restart)
            log_info "重启TCP Ping服务..."
            systemctl restart "${SERVICE_NAME}.service"
            ;;
        status)
            systemctl status "${SERVICE_NAME}.service" --no-pager
            ;;
        logs)
            journalctl -u "${SERVICE_NAME}.service" -f
            ;;
        *)
            log_error "未知的操作: $action"
            log_info "支持的操作: start, stop, restart, status, logs"
            exit 1
            ;;
    esac
}

# 客户端测试
run_client() {
    local host=$1
    local port=$2
    shift 2
    
    # 检查客户端脚本是否存在，如果不存在则创建临时版本
    local client_script_path="${SCRIPT_DIR}/${CLIENT_SCRIPT}"
    if [[ ! -f "$client_script_path" ]]; then
        log_warn "客户端脚本不存在，创建临时版本..."
        mkdir -p "${SCRIPT_DIR}"
        create_client_script
    fi
    
    log_info "运行客户端测试..."
    python3 "$client_script_path" "$host" "$port" "$@"
}

# 显示帮助信息
show_help() {
    cat << EOF
TCP Ping 服务器管理脚本

用法: $0 <命令> [选项]

服务端命令:
  install [host] [port]     安装TCP Ping服务器
                           默认: host=0.0.0.0, port=9966
  uninstall                卸载TCP Ping服务器
  start                    启动服务
  stop                     停止服务
  restart                  重启服务
  status                   查看服务状态
  logs                     查看服务日志

客户端命令:
  test <host> <port> [选项] 测试TCP连接延迟
                           选项: -c 次数 -i 间隔 --type 类型 --data 数据

示例:
  $0 install                    # 安装到默认端口9966
  $0 install 0.0.0.0 8888      # 安装到端口8888
  $0 test 192.168.1.100 9966   # 测试服务器
  $0 test 192.168.1.100 9966 -c 20 -i 0.5  # 自定义测试
  $0 status                     # 查看服务状态
  $0 uninstall                  # 卸载服务

EOF
}

# 主函数
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command=$1
    shift
    
    case $command in
        install)
            check_root
            install_server "$@"
            ;;
        uninstall)
            check_root
            uninstall_server
            ;;
        start|stop|restart|status|logs)
            check_root
            manage_service "$command"
            ;;
        test)
            run_client "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
