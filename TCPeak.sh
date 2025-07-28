#!/bin/bash

# =============================================================================
# TCPeak.sh - 智能TCP参数优化脚本
# =============================================================================
# 开发者: Libyte
# 版本: 250725
# 功能: BBR + BBR2 + 自动调度器 + 延迟追踪 + 日志记录
# 描述: 为VPS服务器提供智能TCP参数调优和sysctl参数自动优化
# =============================================================================

# 显示脚本信息
show_script_info() {
  echo "============================================================================="
  echo "                    TCPeak.sh - 智能TCP参数优化脚本"
  echo "============================================================================="
  echo "开发者: Libyte"
  echo "版本: 250725"
  echo "功能: 智能TCP参数调优 + sysctl参数优化 + 多服务器性能测试"
  echo "支持: BBR/BBR2拥塞控制 + 自动队列调度 + 延迟追踪 + 重传率分析"
  echo "============================================================================="
  echo ""
}

# 显示使用说明
show_usage() {
  echo "📖 使用说明:"
  echo "  1. 确保以root权限或sudo权限运行"
  echo "  2. 脚本会自动检测VPS类型和硬件性能"
  echo "  3. 支持三种VPS类型: 中转机(relay) / 落地机(proxy) / 混合模式(mixed)"
  echo "  4. 支持六种应用场景: 游戏/视频/文件传输/代理/大文件/自定义"
  echo "  5. 自动进行多轮性能测试和参数优化"
  echo ""
  echo "🚀 运行命令:"
  echo "  sudo bash TCPeak.sh"
  echo "  或"
  echo "  chmod +x TCPeak.sh && sudo ./TCPeak.sh"
  echo ""
  echo "⚠️  注意事项:"
  echo "  • 脚本会修改系统内核参数，请确保在测试环境中运行"
  echo "  • 建议在运行前备份当前系统配置"
  echo "  • 某些参数修改可能需要重启系统生效"
  echo "  • 请确保网络连接稳定，避免测试中断"
  echo ""
  echo "📊 输出文件:"
  echo "  • 详细测试报告: ~/tcp_optimization_report_YYYYMMDD_HHMMSS.log"
  echo "  • 配置文件: /etc/sysctl.conf (自动备份)"
  echo ""
}

# 显示脚本信息
show_script_info

# 检查是否显示帮助信息
if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  show_usage
  exit 0
fi

# 显示使用说明
show_usage

# 检查是否为root用户
check_root() {
  if [ "$EUID" -eq 0 ]; then
    echo "检测到root用户，将直接执行命令（不使用sudo）"
    USE_SUDO=""
  else
    echo "检测到普通用户，将使用sudo执行需要权限的命令"
    USE_SUDO="sudo"
  fi
}

# 调用root检查函数
check_root

# 备份系统配置文件
backup_system_config() {
  echo "🔒 备份系统配置文件..."
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  
  # 备份sysctl配置
  if [ -f /etc/sysctl.conf ]; then
    $USE_SUDO cp /etc/sysctl.conf /etc/sysctl.conf.backup.$TIMESTAMP
    echo "✅ 已备份 /etc/sysctl.conf -> /etc/sysctl.conf.backup.$TIMESTAMP"
  fi
  
  # 备份limits配置
  if [ -f /etc/security/limits.conf ]; then
    $USE_SUDO cp /etc/security/limits.conf /etc/security/limits.conf.backup.$TIMESTAMP
    echo "✅ 已备份 /etc/security/limits.conf -> /etc/security/limits.conf.backup.$TIMESTAMP"
  fi
  
  echo "📁 备份完成，时间戳: $TIMESTAMP"
  echo ""
}

# 执行备份
backup_system_config

# 系统兼容性检查
check_system_compatibility() {
  echo "🔍 系统兼容性检查..."
  
  # 检查操作系统
  if [ -f /etc/os-release ]; then
    OS_NAME=$(grep "^NAME=" /etc/os-release | cut -d'"' -f2)
    OS_VERSION=$(grep "^VERSION=" /etc/os-release | cut -d'"' -f2)
    echo "✅ 操作系统: $OS_NAME $OS_VERSION"
  else
    echo "⚠️  无法检测操作系统信息"
  fi
  
  # 检查内核版本
  KERNEL_VERSION=$(uname -r)
  echo "✅ 内核版本: $KERNEL_VERSION"
  
  # 检查架构
  ARCH=$(uname -m)
  echo "✅ 系统架构: $ARCH"
  
  # 检查是否支持BBR
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
    echo "✅ BBR拥塞控制: 支持"
  else
    echo "⚠️  BBR拥塞控制: 不支持 (建议升级内核)"
  fi
  
  # 检查是否支持BBR2
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr2; then
    echo "✅ BBR2拥塞控制: 支持"
  else
    echo "⚠️  BBR2拥塞控制: 不支持 (需要内核5.9+)"
  fi
  
  # 检查网络工具
  if command -v iperf3 >/dev/null 2>&1; then
    echo "✅ iperf3: 已安装"
  else
    echo "⚠️  iperf3: 未安装 (将自动安装)"
  fi
  
  if command -v speedtest-cli >/dev/null 2>&1; then
    echo "✅ speedtest-cli: 已安装"
  else
    echo "⚠️  speedtest-cli: 未安装 (将自动安装)"
  fi
  
  echo ""
}

# 执行兼容性检查
check_system_compatibility

# 用户确认提示
confirm_execution() {
  echo "⚠️  重要提示:"
  echo "  此脚本将修改系统内核参数和网络配置，可能影响系统性能。"
  echo "  请确保您了解这些更改的影响。"
  echo ""
  echo "📋 脚本将执行以下操作:"
  echo "  • 备份当前系统配置"
  echo "  • 安装必要的网络测试工具"
  echo "  • 检测VPS类型和硬件性能"
  echo "  • 进行多轮网络性能测试"
  echo "  • 优化TCP参数和sysctl配置"
  echo "  • 生成详细的测试报告"
  echo ""
  
  read -p "是否继续执行? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 用户取消执行"
    exit 0
  fi
  
  echo "✅ 用户确认执行，开始优化流程..."
  echo ""
}

# 执行用户确认
confirm_execution

REQUIRED_PKGS=(speedtest-cli iperf3 bc iproute2 curl)
echo "检查依赖..."
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "安装 $pkg..."
    $USE_SUDO apt update && $USE_SUDO apt install -y "$pkg"
  fi
done

check_bbr_status() {
  echo "检查 BBR 启用状态..."
  CURRENT_CC=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
  AVAILABLE_CC=$(sysctl net.ipv4.tcp_available_congestion_control)
  if echo "$AVAILABLE_CC" | grep -q bbr; then
    echo "检测到系统支持 BBR"
    if [ "$CURRENT_CC" != "bbr" ] && [ "$CURRENT_CC" != "bbr2" ]; then
      echo "当前未启用 BBR，尝试启用..."
      echo "net.core.default_qdisc=fq" | $USE_SUDO tee -a /etc/sysctl.conf > /dev/null
      echo "net.ipv4.tcp_congestion_control=bbr" | $USE_SUDO tee -a /etc/sysctl.conf > /dev/null
      $USE_SUDO sysctl -p
    else
      echo "BBR 已启用 ($CURRENT_CC)"
    fi
  else
    echo "未检测到可用的 BBR/BBR2。建议升级内核后重试。"
  fi
}

ping_test() {
  local ip=$1
  local avg_rtt=$(ping -c 4 -W 1 "$ip" 2>/dev/null | awk -F'/' '/rtt/ {print $5}' | awk '{print int($1)}')
  # 如果ping失败，返回默认值
  [ -z "$avg_rtt" ] && avg_rtt=50
  echo "$avg_rtt"
}

check_bbr_status

if [ -f ./vps_type.conf ]; then
  source ./vps_type.conf
else
  echo "选择VPS类型: 1=中转机(relay), 2=落地机(proxy), 3=中转+落地机(mixed)"
  read -p "输入 (1/2/3): " TYPE_SELECT
  case "$TYPE_SELECT" in
    1) VPS_TYPE="relay";;
    2) VPS_TYPE="proxy";;
    3) VPS_TYPE="mixed";;
    *) VPS_TYPE="mixed";;
  esac
fi

# 添加应用场景选择功能
echo ""
echo "=== 应用场景选择 ==="
echo "请选择主要应用场景，这将影响重传率阈值设置："
echo "1. 游戏/实时应用 (延迟敏感) - 重传率 < 1%"
echo "2. 视频流媒体 (流畅播放) - 重传率 < 3%"
echo "3. 文件传输/下载 (效率优先) - 重传率 < 5%"
echo "4. 代理服务器 (平衡性能) - 重传率 < 8%"
echo "5. 大文件传输 (可接受) - 重传率 < 10%"
echo "6. 自定义阈值"
echo ""

read -p "选择应用场景 (1-6): " SCENE_SELECT

case "$SCENE_SELECT" in
  1)
    SCENE_NAME="游戏/实时应用"
    RETRANS_WARNING_THRESHOLD=1.0
    RETRANS_NOTE_THRESHOLD=0.5
    RETRANS_NORMAL_THRESHOLD=0.2
    echo "✅ 已选择: $SCENE_NAME (重传率阈值: < 1%)"
    ;;
  2)
    SCENE_NAME="视频流媒体"
    RETRANS_WARNING_THRESHOLD=3.0
    RETRANS_NOTE_THRESHOLD=1.5
    RETRANS_NORMAL_THRESHOLD=0.8
    echo "✅ 已选择: $SCENE_NAME (重传率阈值: < 3%)"
    ;;
  3)
    SCENE_NAME="文件传输/下载"
    RETRANS_WARNING_THRESHOLD=5.0
    RETRANS_NOTE_THRESHOLD=2.5
    RETRANS_NORMAL_THRESHOLD=1.2
    echo "✅ 已选择: $SCENE_NAME (重传率阈值: < 5%)"
    ;;
  4)
    SCENE_NAME="代理服务器"
    RETRANS_WARNING_THRESHOLD=8.0
    RETRANS_NOTE_THRESHOLD=4.0
    RETRANS_NORMAL_THRESHOLD=2.0
    echo "✅ 已选择: $SCENE_NAME (重传率阈值: < 8%)"
    ;;
  5)
    SCENE_NAME="大文件传输"
    RETRANS_WARNING_THRESHOLD=10.0
    RETRANS_NOTE_THRESHOLD=6.0
    RETRANS_NORMAL_THRESHOLD=3.0
    echo "✅ 已选择: $SCENE_NAME (重传率阈值: < 10%)"
    ;;
  6)
    echo "=== 自定义重传率阈值 ==="
    echo "请输入自定义的重传率阈值（百分比）"
    read -p "警告阈值 (> 此值开始警告): " CUSTOM_WARNING
    read -p "注意阈值 (> 此值开始注意): " CUSTOM_NOTE
    read -p "正常阈值 (> 此值视为正常): " CUSTOM_NORMAL
    
    # 验证输入是否为有效数字
    if [[ "$CUSTOM_WARNING" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$CUSTOM_NOTE" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$CUSTOM_NORMAL" =~ ^[0-9]+\.?[0-9]*$ ]]; then
      SCENE_NAME="自定义场景"
      RETRANS_WARNING_THRESHOLD=$CUSTOM_WARNING
      RETRANS_NOTE_THRESHOLD=$CUSTOM_NOTE
      RETRANS_NORMAL_THRESHOLD=$CUSTOM_NORMAL
      echo "✅ 已设置自定义阈值: 警告>$CUSTOM_WARNING%, 注意>$CUSTOM_NOTE%, 正常>$CUSTOM_NORMAL%"
    else
      echo "❌ 输入无效，使用默认代理服务器阈值"
      SCENE_NAME="代理服务器"
      RETRANS_WARNING_THRESHOLD=8.0
      RETRANS_NOTE_THRESHOLD=4.0
      RETRANS_NORMAL_THRESHOLD=2.0
    fi
    ;;
  *)
    echo "❌ 选择无效，使用默认代理服务器阈值"
    SCENE_NAME="代理服务器"
    RETRANS_WARNING_THRESHOLD=8.0
    RETRANS_NOTE_THRESHOLD=4.0
    RETRANS_NORMAL_THRESHOLD=2.0
    ;;
esac

echo "应用场景: $SCENE_NAME"
echo "重传率阈值设置: 警告>$RETRANS_WARNING_THRESHOLD%, 注意>$RETRANS_NOTE_THRESHOLD%, 正常>$RETRANS_NORMAL_THRESHOLD%"
echo ""

# 自动检测VPS性能并选择最优配置模板
auto_detect_performance_mode() {
  # 确保所有变量都是有效的数字，避免算术运算错误
  local cpu_cores=${CPU_CORES:-1}
  local cpu_mhz=${CPU_MHZ:-1000}
  local total_mem_mb=${TOTAL_MEM_MB:-512}
  local iface_speed=${IFACE_SPEED:-2500}
  
  # 验证变量是否为数字
  [[ ! "$cpu_cores" =~ ^[0-9]+$ ]] && cpu_cores=1
  [[ ! "$cpu_mhz" =~ ^[0-9]+$ ]] && cpu_mhz=1000
  [[ ! "$total_mem_mb" =~ ^[0-9]+$ ]] && total_mem_mb=512
  [[ ! "$iface_speed" =~ ^[0-9]+$ ]] && iface_speed=2500
  
  local cpu_score=$((cpu_cores * cpu_mhz / 1000))  # CPU性能得分
  local mem_score=$((total_mem_mb))                 # 内存得分
  local iface_score=$((iface_speed))                # 网络接口得分
  
  # 综合得分计算：CPU(30%) + 内存(40%) + 网络(30%)
  local perf_score=$(((cpu_score * 30 + mem_score * 40 + iface_score * 30) / 100))
  
  echo "=== 智能VPS性能评估 ==="
  echo "CPU性能得分: $cpu_score (${cpu_cores}核 × ${cpu_mhz}MHz)"
  echo "内存得分: $mem_score (${total_mem_mb}MB)"
  echo "网络得分: $iface_score (${iface_speed}Mbps)"
  echo "综合性能得分: $perf_score"
  
  # 特殊情况：低内存但高带宽的VPS (如NAT VPS)
  if [ "$total_mem_mb" -lt 1024 ] && [ "$iface_speed" -ge 1000 ]; then
    PERFORMANCE_MODE="bandwidth_optimized"
    echo "🚀 检测到低内存高带宽VPS → 带宽优化模式"
  elif [ "$perf_score" -ge 3000 ] && [ "$total_mem_mb" -ge 2048 ]; then
    PERFORMANCE_MODE="extreme"
    echo "🔥 检测到高性能服务器 → 极限性能模式"
  elif [ "$perf_score" -ge 1500 ] && [ "$total_mem_mb" -ge 1024 ]; then
    PERFORMANCE_MODE="high"
    echo "⚡ 检测到中高性能VPS → 高性能模式"
  elif [ "$perf_score" -ge 800 ] || [ "$total_mem_mb" -ge 512 ] || [ "$iface_speed" -ge 500 ]; then
    PERFORMANCE_MODE="balanced"
    echo "📊 检测到标准性能VPS → 平衡性能模式"
  else
    PERFORMANCE_MODE="conservative"
    echo "🔒 检测到低配置VPS → 保守稳定模式"
  fi
  
  echo "========================="
}

read -p "输入 iperf3 测试服务器 IP（空格分隔）: " -a IPERF_SERVERS

CPU_CORES=$(nproc)
CPU_MHZ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | awk '{print int($1)}')
MEM_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
echo "CPU: $CPU_CORES 核心 @ ${CPU_MHZ}MHz, 可用内存: ${MEM_MB}MB"

KERNEL_RMEM_MAX=$(cat /proc/sys/net/core/rmem_max)
KERNEL_WMEM_MAX=$(cat /proc/sys/net/core/wmem_max)
SAFE_MAX=$((KERNEL_RMEM_MAX<KERNEL_WMEM_MAX ? KERNEL_RMEM_MAX : KERNEL_WMEM_MAX))
echo "内核缓冲区限制: rmem_max=${KERNEL_RMEM_MAX}, wmem_max=${KERNEL_WMEM_MAX}, SAFE_MAX=${SAFE_MAX}"

KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
BBR2_SUPPORTED=0
if [[ $(echo -e "$KERNEL_VERSION\n5.9" | sort -V | head -n1) == "5.9" ]]; then
  if sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr2; then
    BBR2_SUPPORTED=1
  fi
fi

CAKE_SUPPORTED=0
FQC_SUPPORTED=0
if tc qdisc add dev lo root handle 1: cake 2>/dev/null; then
  CAKE_SUPPORTED=1; tc qdisc del dev lo root 2>/dev/null
fi
if tc qdisc add dev lo root handle 1: fq_codel 2>/dev/null; then
  FQC_SUPPORTED=1; tc qdisc del dev lo root 2>/dev/null
fi

run_speedtest() {
  echo "运行 Speedtest..."
  RESULT=$(speedtest-cli --secure --simple)
  echo "$RESULT"
  DL=$(echo "$RESULT" | grep Download | awk '{print int($2)}')
  UL=$(echo "$RESULT" | grep Upload | awk '{print int($2)}')
}

test_tcp_retransmission() {
  local server=$1
  echo "iperf3 测试 -> $server"
  
  # 运行iperf3测试并捕获重传信息
  local iperf_output=$(iperf3 -c "$server" -t 10 2>&1)
  local iperf_reverse_output=$(iperf3 -c "$server" -t 10 -R 2>&1)
  
  # 调试：显示iperf3输出
  echo "iperf3上行输出:"
  echo "$iperf_output" | tail -5
  echo "iperf3下行输出:"
  echo "$iperf_reverse_output" | tail -5
  
  # 提取速度信息 (更健壮的方法)
  # 处理iperf3输出，可能包含Gbits/sec或Mbits/sec
  # 使用正则表达式精确提取速度值
  DL_SPEED_RAW=$(echo "$iperf_reverse_output" | grep -E "(receiver|sender)" | tail -1 | grep -o '[0-9.]* Gbits/sec\|[0-9.]* Mbits/sec\|[0-9.]* Kbits/sec')
  UL_SPEED_RAW=$(echo "$iperf_output" | grep -E "(receiver|sender)" | tail -1 | grep -o '[0-9.]* Gbits/sec\|[0-9.]* Mbits/sec\|[0-9.]* Kbits/sec')
  
  # 如果正则表达式失败，尝试备用方法
  if [ -z "$DL_SPEED_RAW" ]; then
    DL_SPEED_RAW=$(echo "$iperf_reverse_output" | grep -E "(receiver|sender)" | tail -1 | awk '{print $(NF-2) " " $(NF-1)}')
  fi
  if [ -z "$UL_SPEED_RAW" ]; then
    UL_SPEED_RAW=$(echo "$iperf_output" | grep -E "(receiver|sender)" | tail -1 | awk '{print $(NF-2) " " $(NF-1)}')
  fi
  
  # 调试输出
  echo "调试: DL_RAW='$DL_SPEED_RAW', UL_RAW='$UL_SPEED_RAW'"
  
  # 如果提取失败，显示更多调试信息
  if [ -z "$DL_SPEED_RAW" ] || [ -z "$UL_SPEED_RAW" ]; then
    echo "⚠️  速度提取失败，尝试备用方法..."
    echo "iperf_reverse_output最后一行:"
    echo "$iperf_reverse_output" | grep -E "(receiver|sender)" | tail -1
    echo "iperf_output最后一行:"
    echo "$iperf_output" | grep -E "(receiver|sender)" | tail -1
  fi
  
  # 转换速度单位到Mbps
  DL_SPEED=0
  UL_SPEED=0
  
  if [ -n "$DL_SPEED_RAW" ]; then
    echo "处理DL_SPEED_RAW: '$DL_SPEED_RAW'"
    if echo "$DL_SPEED_RAW" | grep -q "Gbits"; then
      # 如果是Gbits，转换为Mbps
      DL_SPEED=$(echo "$DL_SPEED_RAW" | awk '{print int($1 * 1000)}')
      echo "DL转换: $DL_SPEED_RAW -> ${DL_SPEED}Mbps"
    elif echo "$DL_SPEED_RAW" | grep -q "Mbits"; then
      # 如果是Mbits，直接提取数字
      DL_SPEED=$(echo "$DL_SPEED_RAW" | awk '{print int($1)}')
      echo "DL转换: $DL_SPEED_RAW -> ${DL_SPEED}Mbps"
    elif echo "$DL_SPEED_RAW" | grep -q "Kbits"; then
      # 如果是Kbits，转换为Mbps
      DL_SPEED=$(echo "$DL_SPEED_RAW" | awk '{print int($1 / 1000)}')
      echo "DL转换: $DL_SPEED_RAW -> ${DL_SPEED}Mbps"
    else
      # 假设是数字，直接使用
      DL_SPEED=$(echo "$DL_SPEED_RAW" | awk '{print int($1)}')
      echo "DL转换: $DL_SPEED_RAW -> ${DL_SPEED}Mbps"
    fi
  fi
  
  if [ -n "$UL_SPEED_RAW" ]; then
    echo "处理UL_SPEED_RAW: '$UL_SPEED_RAW'"
    if echo "$UL_SPEED_RAW" | grep -q "Gbits"; then
      # 如果是Gbits，转换为Mbps
      UL_SPEED=$(echo "$UL_SPEED_RAW" | awk '{print int($1 * 1000)}')
      echo "UL转换: $UL_SPEED_RAW -> ${UL_SPEED}Mbps"
    elif echo "$UL_SPEED_RAW" | grep -q "Mbits"; then
      # 如果是Mbits，直接提取数字
      UL_SPEED=$(echo "$UL_SPEED_RAW" | awk '{print int($1)}')
      echo "UL转换: $UL_SPEED_RAW -> ${UL_SPEED}Mbps"
    elif echo "$UL_SPEED_RAW" | grep -q "Kbits"; then
      # 如果是Kbits，转换为Mbps
      UL_SPEED=$(echo "$UL_SPEED_RAW" | awk '{print int($1 / 1000)}')
      echo "UL转换: $UL_SPEED_RAW -> ${UL_SPEED}Mbps"
    else
      # 假设是数字，直接使用
      UL_SPEED=$(echo "$UL_SPEED_RAW" | awk '{print int($1)}')
      echo "UL转换: $UL_SPEED_RAW -> ${UL_SPEED}Mbps"
    fi
  fi
  
  # 确保速度值为有效数字
  [ -z "$DL_SPEED" ] && DL_SPEED=0
  [ -z "$UL_SPEED" ] && UL_SPEED=0
  [ "$DL_SPEED" -lt 0 ] && DL_SPEED=0
  [ "$UL_SPEED" -lt 0 ] && UL_SPEED=0
  
  # 提取重传信息 (更准确的方法)
  # 调试：显示重传提取过程
  echo "重传提取调试:"
  echo "iperf_output sender行:"
  echo "$iperf_output" | grep "sender" | tail -1
  echo "iperf_reverse_output sender行:"
  echo "$iperf_reverse_output" | grep "sender" | tail -1
  
  # 提取重传值，使用更精确的方法
  # 从字段结构分析，重传值是倒数第2个字段（在sender之前）
  local ul_retrans=$(echo "$iperf_output" | grep "sender" | tail -1 | awk '{print $(NF-2)}')
  local dl_retrans=$(echo "$iperf_reverse_output" | grep "sender" | tail -1 | awk '{print $(NF-2)}')
  
  # 如果提取失败，直接使用正则表达式
  if ! [[ "$ul_retrans" =~ ^[0-9]+$ ]]; then
    ul_retrans=$(echo "$iperf_output" | grep "sender" | tail -1 | sed 's/.* \([0-9]\+\)[[:space:]]*sender/\1/')
  fi
  
  if ! [[ "$dl_retrans" =~ ^[0-9]+$ ]]; then
    dl_retrans=$(echo "$iperf_reverse_output" | grep "sender" | tail -1 | sed 's/.* \([0-9]\+\)[[:space:]]*sender/\1/')
  fi
  
  # 验证提取的值是否为数字
  if ! [[ "$ul_retrans" =~ ^[0-9]+$ ]]; then
    echo "⚠️  UL重传值提取失败: '$ul_retrans'，使用正则表达式重新提取"
    ul_retrans=$(echo "$iperf_output" | grep "sender" | tail -1 | sed 's/.* \([0-9]\+\)[[:space:]]*sender/\1/')
    echo "正则表达式提取UL重传值: '$ul_retrans'"
  fi
  
  if ! [[ "$dl_retrans" =~ ^[0-9]+$ ]]; then
    echo "⚠️  DL重传值提取失败: '$dl_retrans'，使用正则表达式重新提取"
    dl_retrans=$(echo "$iperf_reverse_output" | grep "sender" | tail -1 | sed 's/.* \([0-9]\+\)[[:space:]]*sender/\1/')
    echo "正则表达式提取DL重传值: '$dl_retrans'"
  fi
  
  echo "提取的原始重传值: ul_retrans='$ul_retrans', dl_retrans='$dl_retrans'"
  
  # 调试：分析字段结构
  echo "字段结构分析:"
  echo "UL sender行字段数: $(echo "$iperf_output" | grep "sender" | tail -1 | wc -w)"
  echo "UL sender行所有字段: $(echo "$iperf_output" | grep "sender" | tail -1)"
  echo "DL sender行字段数: $(echo "$iperf_reverse_output" | grep "sender" | tail -1 | wc -w)"
  echo "DL sender行所有字段: $(echo "$iperf_reverse_output" | grep "sender" | tail -1)"
  
  # 确保重传值为有效数字
  [ -z "$ul_retrans" ] && ul_retrans=0
  [ -z "$dl_retrans" ] && dl_retrans=0
  
  # 验证重传值是否为数字
  if ! [[ "$ul_retrans" =~ ^[0-9]+$ ]]; then
    echo "⚠️  UL重传值无效: '$ul_retrans'，设为0"
    ul_retrans=0
  fi
  if ! [[ "$dl_retrans" =~ ^[0-9]+$ ]]; then
    echo "⚠️  DL重传值无效: '$dl_retrans'，设为0"
    dl_retrans=0
  fi
  
  [ "$ul_retrans" -lt 0 ] && ul_retrans=0
  [ "$dl_retrans" -lt 0 ] && dl_retrans=0
  
  # 计算平均重传率 (修正计算方法)
  local total_retrans=$((ul_retrans + dl_retrans))
  
  # 估算总数据包数 (基于带宽和MTU)
  # 假设平均MTU为1500字节，计算数据包数量
  local mtu_bytes=1500
  local ul_packets=0
  local dl_packets=0
  
  if [ "$UL_SPEED" -gt 0 ]; then
    # 上行数据包数 = 带宽(bps) * 时间(10秒) / (MTU * 8)
    ul_packets=$(echo "scale=0; $UL_SPEED * 1000000 * 10 / ($mtu_bytes * 8)" | bc 2>/dev/null || echo "0")
  fi
  
  if [ "$DL_SPEED" -gt 0 ]; then
    # 下行数据包数 = 带宽(bps) * 时间(10秒) / (MTU * 8)
    dl_packets=$(echo "scale=0; $DL_SPEED * 1000000 * 10 / ($mtu_bytes * 8)" | bc 2>/dev/null || echo "0")
  fi
  
  local total_packets=$((ul_packets + dl_packets))
  RETRANS_RATE=0
  
  echo "重传计算: total_retrans=$total_retrans, total_packets=$total_packets"
  echo "数据包估算: UL=${UL_SPEED}Mbps -> ${ul_packets}包, DL=${DL_SPEED}Mbps -> ${dl_packets}包"
  echo "重传率验证: $total_retrans / $total_packets * 100 = $(echo "scale=3; $total_retrans * 100 / $total_packets" | bc 2>/dev/null || echo "计算失败")%"
  echo "重传率详细计算: 上行${ul_packets}包重传${ul_retrans}次($(echo "scale=3; $ul_retrans * 100 / $ul_packets" | bc 2>/dev/null || echo "0")%), 下行${dl_packets}包重传${dl_retrans}次($(echo "scale=3; $dl_retrans * 100 / $dl_packets" | bc 2>/dev/null || echo "0")%)"
  
  if [ "$total_packets" -gt 0 ] && [ "$total_retrans" -ge 0 ]; then
    # 使用更安全的计算方法
    if [ "$total_retrans" -eq 0 ]; then
      RETRANS_RATE=0
      echo "重传率为0"
    else
      # 计算重传率
      local retrans_percent=$(echo "scale=3; $total_retrans * 100 / $total_packets" | bc 2>/dev/null || echo "0")
      if [ -n "$retrans_percent" ] && [ "$retrans_percent" != "0" ]; then
        RETRANS_RATE=$retrans_percent
        echo "计算重传率: $retrans_percent%"
      else
        RETRANS_RATE=0
        echo "重传率计算失败，设为0"
      fi
    fi
  else
    echo "跳过重传率计算: total_packets=$total_packets, total_retrans=$total_retrans"
  fi
  
  # 确保重传率在合理范围内
  if compare_float "$RETRANS_RATE" ">" "50"; then
    RETRANS_RATE=50  # 限制最大重传率为50%
  fi
  
  # 计算平均速度 (避免除零错误)
  if [ "$DL_SPEED" -eq 0 ] && [ "$UL_SPEED" -eq 0 ]; then
    AVG_IPERF=0
  else
  AVG_IPERF=$(( (DL_SPEED + UL_SPEED) / 2 ))
  fi
  PING_RTT=$(ping_test "$server")
  
  echo "UL: ${UL_SPEED}Mbps, DL: ${DL_SPEED}Mbps, AVG: ${AVG_IPERF}Mbps, RTT: ${PING_RTT}ms"
  echo "重传统计: UL重传=$ul_retrans, DL重传=$dl_retrans, 平均重传率=${RETRANS_RATE}%"
  echo "调试信息: DL_RAW='$DL_SPEED_RAW', UL_RAW='$UL_SPEED_RAW'"
  
  # 专业重传率评估说明 (动态显示)
  echo ""
  echo "📊 ${SCENE_NAME}重传率评估标准:"
  echo "  • < 0.5%: 网络质量极佳 (超出${SCENE_NAME}要求)"
  echo "  • 0.5-${RETRANS_NORMAL_THRESHOLD}%: 网络质量良好 (符合${SCENE_NAME}要求)"
  echo "  • ${RETRANS_NORMAL_THRESHOLD}-${RETRANS_NOTE_THRESHOLD}%: 网络质量正常 (轻微超出${SCENE_NAME}要求)"
  echo "  • ${RETRANS_NOTE_THRESHOLD}-${RETRANS_WARNING_THRESHOLD}%: 网络质量可接受 (超出${SCENE_NAME}建议)"
  echo "  • > ${RETRANS_WARNING_THRESHOLD}%: 网络质量较差 (严重超出${SCENE_NAME}阈值)"
  echo ""
  
  # 重传率警告 (动态阈值 - 基于应用场景)
  if compare_float "$RETRANS_RATE" ">" "$RETRANS_WARNING_THRESHOLD"; then
    echo "🚨 严重：重传率过高 (${RETRANS_RATE}%)，超过${SCENE_NAME}阈值(${RETRANS_WARNING_THRESHOLD}%)，需要大幅调整网络参数"
  elif compare_float "$RETRANS_RATE" ">" "$RETRANS_NOTE_THRESHOLD"; then
    echo "⚠️  警告：重传率较高 (${RETRANS_RATE}%)，超过${SCENE_NAME}注意阈值(${RETRANS_NOTE_THRESHOLD}%)，建议调整网络参数"
  elif compare_float "$RETRANS_RATE" ">" "$RETRANS_NORMAL_THRESHOLD"; then
    echo "📊 注意：重传率中等 (${RETRANS_RATE}%)，超过${SCENE_NAME}正常阈值(${RETRANS_NORMAL_THRESHOLD}%)，可适度调整参数"
  elif compare_float "$RETRANS_RATE" ">" "0.5"; then
    echo "✅ 良好：重传率较低 (${RETRANS_RATE}%)，符合${SCENE_NAME}要求"
  else
    echo "🌟 优秀：重传率很低 (${RETRANS_RATE}%)，${SCENE_NAME}网络质量极佳"
  fi
}

# 安全的浮点数比较函数
compare_float() {
  local val1=$1
  local op=$2
  local val2=$3
  
  # 确保输入值不为空，如果为空则设为0
  [ -z "$val1" ] && val1="0"
  [ -z "$val2" ] && val2="0"
  
  # 使用awk进行浮点数比较，避免bc语法错误
  result=$(awk "BEGIN { if ($val1 $op $val2) print 1; else print 0 }")
  [ "$result" -eq 1 ]
}

# 详细的硬件性能检测函数
detect_hardware() {
  echo "=== 硬件性能检测 ==="
  
  # CPU信息检测
  CPU_CORES=$(nproc)
  CPU_MHZ=$(awk -F: '/cpu MHz/ {print $2; exit}' /proc/cpuinfo | awk '{print int($1)}')
  [ -z "$CPU_MHZ" ] && CPU_MHZ=1000  # 默认值
  CPU_ARCH=$(uname -m)
  CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//')
  
  # 内存信息检测
  TOTAL_MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  AVAIL_MEM_KB=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
  MEM_MB=$((AVAIL_MEM_KB / 1024))
  
  # 交换分区检测
  SWAP_TOTAL_KB=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
  SWAP_FREE_KB=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
  SWAP_TOTAL_MB=$((SWAP_TOTAL_KB / 1024))
  
  # 磁盘IO性能检测
  DISK_ROOT=$(df / | tail -1 | awk '{print $1}')
  DISK_TYPE="unknown"
  if [ -e "/sys/block/$(basename $DISK_ROOT | sed 's/[0-9]*$//')/" ]; then
    ROTATIONAL=$(cat /sys/block/$(basename $DISK_ROOT | sed 's/[0-9]*$//')/queue/rotational 2>/dev/null)
    [ "$ROTATIONAL" = "0" ] && DISK_TYPE="SSD" || DISK_TYPE="HDD"
  fi
  
  # 网络接口检测
  PRIMARY_IFACE=$(ip route | grep default | head -1 | awk '{print $5}')
  IFACE_SPEED=$(ethtool "$PRIMARY_IFACE" 2>/dev/null | grep "Speed:" | awk '{print $2}' | sed 's/Mb\/s//') 
  
  # 确保IFACE_SPEED是有效的数字，如果不是则使用默认值
  if [[ ! "$IFACE_SPEED" =~ ^[0-9]+$ ]]; then
    echo "⚠️  网络接口速度检测失败，使用默认值2500Mbps (2.5G)"
    IFACE_SPEED=2500
  fi
  
  # 如果为空，也使用默认值
  [ -z "$IFACE_SPEED" ] && IFACE_SPEED=2500
  
  echo "CPU: $CPU_CORES 核心 @ ${CPU_MHZ}MHz ($CPU_ARCH)"
  echo "CPU型号: $CPU_MODEL"
  echo "总内存: ${TOTAL_MEM_MB}MB, 可用内存: ${MEM_MB}MB"
  echo "交换分区: ${SWAP_TOTAL_MB}MB"
  echo "磁盘类型: $DISK_TYPE"
  echo "网络接口: $PRIMARY_IFACE @ ${IFACE_SPEED}Mbps"
  echo "========================"
  
  # 自动检测并设置性能模式
  auto_detect_performance_mode
}

# 动态计算最优参数
calculate_optimal_params() {
  local bw=$1
  local loss=$2
  local ping_rtt=$3
  local round=$4
  # PERFORMANCE_MODE 作为全局变量使用
  
  # 确保参数不为空
  [ -z "$bw" ] && bw=100
  [ -z "$loss" ] && loss=0
  [ -z "$ping_rtt" ] && ping_rtt=50
  
  # 基于硬件性能和网络条件计算参数
  
  # 1. 智能缓冲区配置 (基于VPS类型和性能模式)
  case "$VPS_TYPE" in
    "relay")
      # 中转机：优化上行传输，平衡多个落地机
      echo "🔄 中转机配置：优化上行带宽和连接稳定性"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            BUFFER=33554432; INIT_CWND=150; TIMEOUT=30  # 32MB，平衡配置
          else
            BUFFER=16777216; INIT_CWND=100; TIMEOUT=25  # 16MB
          fi
          ;;
        "extreme")
          BUFFER=167772160; INIT_CWND=250; TIMEOUT=35   # 160MB
          ;;
        "high")
          if [ "$bw" -gt 800 ]; then
            BUFFER=83886080; INIT_CWND=180; TIMEOUT=30  # 80MB
          else
            BUFFER=41943040; INIT_CWND=120; TIMEOUT=25  # 40MB
          fi
          ;;
        *)
          # 平衡/保守模式：基于BDP计算
          if [ "$ping_rtt" -eq 0 ] || [ "$ping_rtt" -lt 1 ]; then
            # 如果ping为0或太小，使用带宽的1/8作为基础计算
            BDP=$((bw * 1024 * 10 / 8))  # 使用10ms作为默认RTT
            echo "BDP计算: 带宽${bw}Mbps, RTT=10ms(默认), BDP=${BDP}字节"
          else
            BDP=$((bw * 1024 * ping_rtt / 8))
            echo "BDP计算: 带宽${bw}Mbps, RTT=${ping_rtt}ms, BDP=${BDP}字节"
          fi
          BUFFER=$((BDP * 15))  # 中转机使用更大的乘数
          echo "缓冲区计算: BDP=${BDP} * 15 = ${BUFFER}字节 ($((BUFFER/1024/1024))MB)"
          [ "$BUFFER" -lt 15728640 ] && BUFFER=15728640   # 最小15MB
          [ "$BUFFER" -gt 83886080 ] && BUFFER=83886080   # 最大80MB
          INIT_CWND=80; TIMEOUT=20
          ;;
      esac
      ;;
    "proxy")
      # 落地机：优化下行接收和延迟稳定性
      echo "🌐 落地机配置：优化下行带宽和延迟稳定性"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            BUFFER=50331648; INIT_CWND=200; TIMEOUT=35  # 48MB，充分利用带宽
          else
            BUFFER=25165824; INIT_CWND=140; TIMEOUT=30  # 24MB
          fi
          ;;
        "extreme")
          BUFFER=268435456; INIT_CWND=350; TIMEOUT=40   # 256MB
          ;;
        "high")
          if [ "$bw" -gt 800 ]; then
            BUFFER=134217728; INIT_CWND=250; TIMEOUT=35 # 128MB
          else
            BUFFER=67108864; INIT_CWND=180; TIMEOUT=30  # 64MB
          fi
          ;;
        *)
          # 平衡/保守模式：基于BDP计算
          if [ "$ping_rtt" -eq 0 ] || [ "$ping_rtt" -lt 1 ]; then
            # 如果ping为0或太小，使用带宽的1/8作为基础计算
            BDP=$((bw * 1024 * 10 / 8))  # 使用10ms作为默认RTT
          else
            BDP=$((bw * 1024 * ping_rtt / 8))
          fi
          BUFFER=$((BDP * 18))  # 落地机使用更大的乘数
          [ "$BUFFER" -lt 18874368 ] && BUFFER=18874368   # 最小18MB
          [ "$BUFFER" -gt 100663296 ] && BUFFER=100663296 # 最大96MB
          INIT_CWND=100; TIMEOUT=25
          ;;
      esac
      ;;
    "mixed")
      # 混合模式：平衡上下行，全能配置
      echo "⚖️  混合模式配置：平衡上下行带宽和稳定性"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            BUFFER=37748736; INIT_CWND=175; TIMEOUT=32  # 36MB，平衡配置
          else
            BUFFER=18874368; INIT_CWND=120; TIMEOUT=27  # 18MB
          fi
          ;;
        "extreme")
          BUFFER=201326592; INIT_CWND=300; TIMEOUT=37   # 192MB
          ;;
        "high")
          if [ "$bw" -gt 800 ]; then
            BUFFER=100663296; INIT_CWND=220; TIMEOUT=32 # 96MB
          else
            BUFFER=50331648; INIT_CWND=150; TIMEOUT=27  # 48MB
          fi
          ;;
        *)
          # 平衡/保守模式：基于BDP计算
          if [ "$ping_rtt" -eq 0 ] || [ "$ping_rtt" -lt 1 ]; then
            # 如果ping为0或太小，使用带宽的1/8作为基础计算
            BDP=$((bw * 1024 * 10 / 8))  # 使用10ms作为默认RTT
          else
            BDP=$((bw * 1024 * ping_rtt / 8))
          fi
          BUFFER=$((BDP * 16))  # 混合模式使用中等乘数
          [ "$BUFFER" -lt 16777216 ] && BUFFER=16777216   # 最小16MB
          [ "$BUFFER" -gt 92274688 ] && BUFFER=92274688   # 最大88MB
          INIT_CWND=90; TIMEOUT=22
          ;;
      esac
      ;;
  esac
  
  echo "缓冲区配置: $((BUFFER/1024/1024))MB, 初始窗口: $INIT_CWND, 超时: ${TIMEOUT}s"
  echo "调试: BUFFER原始值=$BUFFER 字节"
  
  # 2. 基于内存限制缓冲区 (优化策略 - 避免过度限制)
  # 确保MEM_MB是有效数字
  local mem_mb_buffer=${MEM_MB:-512}
  [[ ! "$mem_mb_buffer" =~ ^[0-9]+$ ]] && mem_mb_buffer=512
  
  case "$PERFORMANCE_MODE" in
    "bandwidth_optimized")
      # 带宽优化模式：适中的内存使用（可用内存的1/4）
      MAX_BUFFER_BY_MEM=$((mem_mb_buffer * 1024 * 256))
      [ "$BUFFER" -gt "$MAX_BUFFER_BY_MEM" ] && BUFFER=$MAX_BUFFER_BY_MEM
      echo "🔒 内存保护：限制缓冲区为可用内存的1/4 (${MAX_BUFFER_BY_MEM}字节)"
      ;;
    "extreme"|"high")
      # 高性能模式：激进的内存使用（可用内存的1/2）
      MAX_BUFFER_BY_MEM=$((mem_mb_buffer * 1024 * 512))
      [ "$BUFFER" -gt "$MAX_BUFFER_BY_MEM" ] && BUFFER=$MAX_BUFFER_BY_MEM
      echo "🔒 内存保护：限制缓冲区为可用内存的1/2 (${MAX_BUFFER_BY_MEM}字节)"
      ;;
    *)
      # 平衡模式：标准内存使用（可用内存的1/2）
      MAX_BUFFER_BY_MEM=$((mem_mb_buffer * 1024 * 512))
      [ "$BUFFER" -gt "$MAX_BUFFER_BY_MEM" ] && BUFFER=$MAX_BUFFER_BY_MEM
      echo "🔒 内存保护：限制缓冲区为可用内存的1/2 (${MAX_BUFFER_BY_MEM}字节)"
      ;;
  esac
  
  # 检查SAFE_MAX是否过小，如果是则使用更合理的限制
  if [ "$SAFE_MAX" -lt 10485760 ]; then  # 如果小于10MB
    echo "⚠️  内核缓冲区限制过小(${SAFE_MAX}字节)，使用最小10MB限制"
    SAFE_MAX=10485760  # 设置为10MB
  fi
  
  [ "$BUFFER" -gt "$SAFE_MAX" ] && BUFFER=$SAFE_MAX
  echo "调试: 内存限制后BUFFER=$BUFFER 字节"

  # 3. 基于丢包率和重传率智能调整
  # 计算重传率 (如果iperf3测试可用)
  local retrans_rate=0
  if [ -n "$RETRANS_RATE" ] && [ "$RETRANS_RATE" != "0" ]; then
    retrans_rate=$RETRANS_RATE
  fi
  
  # 综合评估网络质量 (动态阈值 - 基于应用场景)
  local network_quality_score=0
  if compare_float "$loss" ">" "5"; then
    network_quality_score=$((network_quality_score + 3))
  elif compare_float "$loss" ">" "2"; then
    network_quality_score=$((network_quality_score + 2))
  elif compare_float "$loss" ">" "1"; then
    network_quality_score=$((network_quality_score + 1))
  fi
  
  # 基于应用场景的动态重传率评估
  if compare_float "$retrans_rate" ">" "$RETRANS_WARNING_THRESHOLD"; then
    network_quality_score=$((network_quality_score + 4))  # 严重问题
  elif compare_float "$retrans_rate" ">" "$RETRANS_NOTE_THRESHOLD"; then
    network_quality_score=$((network_quality_score + 3))  # 需要调整
  elif compare_float "$retrans_rate" ">" "$RETRANS_NORMAL_THRESHOLD"; then
    network_quality_score=$((network_quality_score + 2))  # 中等问题
  elif compare_float "$retrans_rate" ">" "0.5"; then
    network_quality_score=$((network_quality_score + 1))  # 轻微问题
  fi
  
  # 根据网络质量调整参数 (优化策略 - 避免过度限制缓冲区)
  if [ "$network_quality_score" -ge 5 ]; then
    echo "🚨 检测到网络质量严重问题 (丢包:${loss}%, 重传:${retrans_rate}%)，适度降低缓冲区"
    [ "$BUFFER" -gt 0 ] && BUFFER=$((BUFFER * 2 / 3)) || BUFFER=5242880  # 最小5MB
    [ "$INIT_CWND" -gt 0 ] && INIT_CWND=$((INIT_CWND * 3 / 4)) || INIT_CWND=15
    TIMEOUT=$((TIMEOUT + 3))  # 适度增加超时时间
  elif [ "$network_quality_score" -ge 4 ]; then
    echo "⚠️  检测到网络质量较差 (丢包:${loss}%, 重传:${retrans_rate}%)，轻微降低缓冲区"
    [ "$BUFFER" -gt 0 ] && BUFFER=$((BUFFER * 4 / 5)) || BUFFER=6291456  # 最小6MB
    [ "$INIT_CWND" -gt 0 ] && INIT_CWND=$((INIT_CWND * 9 / 10)) || INIT_CWND=18
    TIMEOUT=$((TIMEOUT + 2))  # 轻微增加超时时间
  elif [ "$network_quality_score" -ge 2 ]; then
    echo "📊 检测到网络质量一般 (丢包:${loss}%, 重传:${retrans_rate}%)，保持大部分配置"
    [ "$BUFFER" -gt 0 ] && BUFFER=$((BUFFER * 9 / 10)) || BUFFER=7340032  # 最小7MB
    [ "$INIT_CWND" -gt 0 ] && INIT_CWND=$((INIT_CWND * 95 / 100)) || INIT_CWND=19
    TIMEOUT=$((TIMEOUT + 1))
  elif [ "$network_quality_score" -ge 1 ]; then
    echo "📊 检测到轻微网络问题 (丢包:${loss}%, 重传:${retrans_rate}%)，几乎不调整"
    [ "$BUFFER" -gt 0 ] && BUFFER=$((BUFFER * 95 / 100)) || BUFFER=8388608  # 最小8MB
  else
    echo "✅ 网络质量良好 (丢包:${loss}%, 重传:${retrans_rate}%)，保持激进配置"
  fi
  
  echo "调试: 网络质量调整后BUFFER=$BUFFER 字节"
  
  # 4. 智能队列配置 (基于VPS类型和性能模式)
  case "$VPS_TYPE" in
    "relay")
      # 中转机：需要处理多个落地机连接，队列要大
      echo "🔄 中转机队列配置：优化多连接处理能力"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            SOMAXCONN=98304; MAX_SYN_BACKLOG=49152; NETDEV_BACKLOG=40000
            echo "中转机带宽优化队列: 9.8万连接队列 (高带宽)"
          else
            SOMAXCONN=49152; MAX_SYN_BACKLOG=24576; NETDEV_BACKLOG=24000
            echo "中转机带宽优化队列: 4.9万连接队列 (中带宽)"
          fi
          ;;
        "extreme")
          SOMAXCONN=196608; MAX_SYN_BACKLOG=98304; NETDEV_BACKLOG=60000
          echo "中转机极限队列: 19万连接队列"
          ;;
        "high")
          if [ "$bw" -gt 800 ] || [ "$CPU_CORES" -ge 2 ]; then
            SOMAXCONN=98304; MAX_SYN_BACKLOG=49152; NETDEV_BACKLOG=30000
            echo "中转机高性能队列: 9.8万连接队列"
          else
            SOMAXCONN=49152; MAX_SYN_BACKLOG=24576; NETDEV_BACKLOG=15000
            echo "中转机高性能队列: 4.9万连接队列"
          fi
          ;;
        *)
          SOMAXCONN=49152; MAX_SYN_BACKLOG=24576; NETDEV_BACKLOG=16000
          echo "中转机平衡队列: 4.9万连接队列"
          ;;
      esac
      ;;
    "proxy")
      # 落地机：主要处理网站连接，队列适中
      echo "🌐 落地机队列配置：优化网站连接处理"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            SOMAXCONN=65536; MAX_SYN_BACKLOG=32768; NETDEV_BACKLOG=30000
            echo "落地机带宽优化队列: 6.5万连接队列 (高带宽)"
          else
            SOMAXCONN=32768; MAX_SYN_BACKLOG=16384; NETDEV_BACKLOG=16000
            echo "落地机带宽优化队列: 3.2万连接队列 (中带宽)"
          fi
          ;;
        "extreme")
          SOMAXCONN=131072; MAX_SYN_BACKLOG=65536; NETDEV_BACKLOG=50000
          echo "落地机极限队列: 13万连接队列"
          ;;
        "high")
          if [ "$bw" -gt 800 ] || [ "$CPU_CORES" -ge 2 ]; then
            SOMAXCONN=65536; MAX_SYN_BACKLOG=32768; NETDEV_BACKLOG=20000
            echo "落地机高性能队列: 6.5万连接队列"
          else
            SOMAXCONN=32768; MAX_SYN_BACKLOG=16384; NETDEV_BACKLOG=10000
            echo "落地机高性能队列: 3.2万连接队列"
          fi
          ;;
        *)
          SOMAXCONN=32768; MAX_SYN_BACKLOG=16384; NETDEV_BACKLOG=10000
          echo "落地机平衡队列: 3.2万连接队列"
          ;;
      esac
      ;;
    "mixed")
      # 混合模式：平衡中转和落地需求
      echo "⚖️  混合模式队列配置：平衡多连接和稳定性"
      case "$PERFORMANCE_MODE" in
        "bandwidth_optimized")
          if [ "$bw" -gt 1000 ]; then
            SOMAXCONN=81920; MAX_SYN_BACKLOG=40960; NETDEV_BACKLOG=35000
            echo "混合模式带宽优化队列: 8.1万连接队列 (高带宽)"
          else
            SOMAXCONN=40960; MAX_SYN_BACKLOG=20480; NETDEV_BACKLOG=20000
            echo "混合模式带宽优化队列: 4万连接队列 (中带宽)"
          fi
          ;;
        "extreme")
          SOMAXCONN=163840; MAX_SYN_BACKLOG=81920; NETDEV_BACKLOG=55000
          echo "混合模式极限队列: 16万连接队列"
          ;;
        "high")
          if [ "$bw" -gt 800 ] || [ "$CPU_CORES" -ge 2 ]; then
            SOMAXCONN=81920; MAX_SYN_BACKLOG=40960; NETDEV_BACKLOG=25000
            echo "混合模式高性能队列: 8.1万连接队列"
          else
            SOMAXCONN=40960; MAX_SYN_BACKLOG=20480; NETDEV_BACKLOG=12500
            echo "混合模式高性能队列: 4万连接队列"
          fi
          ;;
        *)
          SOMAXCONN=40960; MAX_SYN_BACKLOG=20480; NETDEV_BACKLOG=13000
          echo "混合模式平衡队列: 4万连接队列"
          ;;
      esac
      ;;
  esac
  
  # 5. 进程和内存参数
  # 确保CPU_CORES和MEM_MB是有效数字
  local cpu_cores_safe=${CPU_CORES:-1}
  local mem_mb_safe=${MEM_MB:-512}
  [[ ! "$cpu_cores_safe" =~ ^[0-9]+$ ]] && cpu_cores_safe=1
  [[ ! "$mem_mb_safe" =~ ^[0-9]+$ ]] && mem_mb_safe=512
  
  PID_MAX=$((cpu_cores_safe * 16384))
  [ "$PID_MAX" -gt 131072 ] && PID_MAX=131072
  [ "$PID_MAX" -lt 32768 ] && PID_MAX=32768
  
  MIN_FREE_KBYTES=$((mem_mb_safe * 64))  # 总内存的约6%作为最小空闲内存
  [ "$MIN_FREE_KBYTES" -gt 1048576 ] && MIN_FREE_KBYTES=1048576  # 最大1GB
  [ "$MIN_FREE_KBYTES" -lt 65536 ] && MIN_FREE_KBYTES=65536      # 最小64MB
  
    # 6. 基于自动检测的性能模板智能调优
  case "$PERFORMANCE_MODE" in
    "bandwidth_optimized")
      echo "🚀 应用带宽优化配置：低内存高带宽专用优化"
      # 针对低内存场景的特殊优化：适度使用swap，激进网络配置
      VM_SWAPPINESS=20  # 允许适度swap，避免OOM
      VM_DIRTY_RATIO=15  # 较低脏页比例，及时写入
      VM_DIRTY_BG_RATIO=5
      VM_VFS_CACHE_PRESSURE=200  # 适中的缓存压力
      VM_OVERCOMMIT=1
      TCP_ORPHANS=524288   # 提升TCP连接数到50万
      CONNTRACK_MAX=2097152  # 提升到200万连接跟踪
      ;;
    "extreme")
      echo "🔥 应用极限性能配置：不顾一切追求最高性能"
      VM_SWAPPINESS=1
      VM_DIRTY_RATIO=80
      VM_DIRTY_BG_RATIO=25
      VM_VFS_CACHE_PRESSURE=1000
      VM_OVERCOMMIT=1
      TCP_ORPHANS=2097152
      CONNTRACK_MAX=16777216
      ;;
    "high")
      echo "⚡ 应用高性能配置：充分挖掘VPS潜力"
      VM_SWAPPINESS=1
      VM_DIRTY_RATIO=50
      VM_DIRTY_BG_RATIO=18
      VM_VFS_CACHE_PRESSURE=500
      VM_OVERCOMMIT=1
      TCP_ORPHANS=1048576
      CONNTRACK_MAX=8388608
      ;;
    "balanced")
      echo "📊 应用平衡性能配置：性能与稳定并重"
      VM_SWAPPINESS=5
      VM_DIRTY_RATIO=30
      VM_DIRTY_BG_RATIO=10
      VM_VFS_CACHE_PRESSURE=300
      VM_OVERCOMMIT=1
      TCP_ORPHANS=1048576
      CONNTRACK_MAX=8388608
      ;;
    "conservative")
      echo "🔒 应用保守配置：稳定性优先"
      VM_SWAPPINESS=15
      VM_DIRTY_RATIO=20
      VM_DIRTY_BG_RATIO=6
      VM_VFS_CACHE_PRESSURE=150
      VM_OVERCOMMIT=1
      TCP_ORPHANS=262144
      CONNTRACK_MAX=2097152
      ;;
  esac
  
  # 7. 智能拥塞控制选择 (基于网络质量)
  if [ "$network_quality_score" -ge 3 ]; then
    # 网络质量较差时，使用更保守的拥塞控制
    if [ "$BBR2_SUPPORTED" -eq 1 ]; then
      CONGESTION="bbr2"
      echo "🌐 网络质量较差，使用BBR2拥塞控制"
    else
      CONGESTION="bbr"
      echo "🌐 网络质量较差，使用BBR拥塞控制"
    fi
  else
    # 网络质量良好时，使用激进配置
  CONGESTION="bbr"
  [ "$BBR2_SUPPORTED" -eq 1 ] && CONGESTION="bbr2"
    echo "🌐 网络质量良好，使用${CONGESTION}拥塞控制"
  fi

  # 8. 选择队列调度算法
  # 使用安全的CPU变量
  local cpu_cores_qdisc=${CPU_CORES:-1}
  local cpu_mhz_qdisc=${CPU_MHZ:-1000}
  [[ ! "$cpu_cores_qdisc" =~ ^[0-9]+$ ]] && cpu_cores_qdisc=1
  [[ ! "$cpu_mhz_qdisc" =~ ^[0-9]+$ ]] && cpu_mhz_qdisc=1000
  
  if [ "$bw" -lt 100 ] && [ "$CAKE_SUPPORTED" -eq 1 ] && [ "$cpu_cores_qdisc" -ge 2 ] && [ "$cpu_mhz_qdisc" -ge 1800 ]; then
    QDISC="cake"
  elif [ "$bw" -lt 500 ] && [ "$FQC_SUPPORTED" -eq 1 ]; then
    QDISC="fq_codel"
  else
    QDISC="fq"
  fi

       # 9. 端口范围 (最大化可用端口，提升性能)
  PORT_RANGE_START=1024
  PORT_RANGE_END=65535
}

adjust_tcp() {
  local bw=$1
  local loss=$2
  local ping_rtt=$3
  local round=$4
  
  # 检测硬件性能
  detect_hardware
  
  # 计算最优参数
  calculate_optimal_params "$bw" "$loss" "$ping_rtt" "$round"
  
  echo "====== 智能TCP优化配置摘要 ======"
  echo "🎯 VPS类型: $VPS_TYPE | 性能模式: $PERFORMANCE_MODE"
  echo "📱 应用场景: $SCENE_NAME | 重传率阈值: ${RETRANS_WARNING_THRESHOLD}%"
  echo "💾 缓冲区: $((BUFFER/1024/1024))MB (${BUFFER}字节) | 拥塞控制: $CONGESTION | 队列调度: $QDISC"  
  echo "🔗 连接队列: $SOMAXCONN | 网络队列: $NETDEV_BACKLOG | SYN队列: $MAX_SYN_BACKLOG"
  echo "⚙️  内存参数: swappiness=$VM_SWAPPINESS | dirty_ratio=$VM_DIRTY_RATIO"
  echo "🌐 TCP设置: orphans=$TCP_ORPHANS | conntrack=$CONNTRACK_MAX | init_cwnd=$INIT_CWND"
  echo "================================="

$USE_SUDO tee /etc/sysctl.conf > /dev/null <<EOF
# ============ 内核参数 ============
kernel.pid_max = $PID_MAX
kernel.panic = 1
kernel.sysrq = 1
kernel.core_pattern = core_%e_%p_%t
kernel.printk = 3 4 1 3
kernel.numa_balancing = 0
kernel.sched_autogroup_enabled = 0
# ============ 虚拟内存管理 (智能调整) ============
vm.swappiness = $VM_SWAPPINESS
vm.dirty_ratio = $VM_DIRTY_RATIO
vm.dirty_background_ratio = $VM_DIRTY_BG_RATIO
vm.panic_on_oom = 0
vm.overcommit_memory = $VM_OVERCOMMIT
vm.min_free_kbytes = $MIN_FREE_KBYTES
vm.vfs_cache_pressure = $VM_VFS_CACHE_PRESSURE
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 100

# ============ 网络核心参数 (高性能配置) ============
net.core.default_qdisc = $QDISC
net.core.netdev_max_backlog = $NETDEV_BACKLOG
net.core.rmem_max = $BUFFER
net.core.wmem_max = $BUFFER
net.core.rmem_default = 524288
net.core.wmem_default = 524288
net.core.somaxconn = $SOMAXCONN
net.core.optmem_max = 524288
net.core.netdev_budget = 2400
net.core.netdev_budget_usecs = 16000
net.core.dev_weight = 256

# ============ IPv4 TCP参数 (重传率优化) ============
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = $TIMEOUT
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 1048576
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = -2
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_no_metrics_save = 0
net.ipv4.tcp_frto = 2
net.ipv4.tcp_early_retrans = 3
net.ipv4.tcp_thin_linear_timeouts = 1
net.ipv4.tcp_recovery = 1
net.ipv4.tcp_rmem = 65536 524288 $BUFFER
net.ipv4.tcp_wmem = 65536 524288 $BUFFER

# ============ TCP缓冲区配置 (超大缓冲区) ============
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = $CONGESTION
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_limit_output_bytes = 2097152

# ============ TCP连接管理 (重传优化) ============
net.ipv4.tcp_max_syn_backlog = $MAX_SYN_BACKLOG
net.ipv4.tcp_max_orphans = $TCP_ORPHANS
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_stdurg = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_syncookies = 0
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 2
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 15

# ============ IP参数配置 ============
net.ipv4.ip_local_port_range = $PORT_RANGE_START $PORT_RANGE_END
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.ip_forward = 1
net.ipv4.route.gc_timeout = 100

# ============ 邻居表优化 ============
net.ipv4.neigh.default.gc_stale_time = 120
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh3 = 8192
net.ipv6.neigh.default.gc_thresh2 = 4096
net.ipv6.neigh.default.gc_thresh1 = 1024

# ============ 性能优先配置 (减少安全限制) ============
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.arp_announce = 0
net.ipv4.conf.default.arp_announce = 0
net.ipv4.conf.all.arp_ignore = 0
net.ipv4.conf.default.arp_ignore = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# ============ IPv6支持 ============
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# ============ 网络过滤器 (转发代理优化) ============
net.netfilter.nf_conntrack_max = $CONNTRACK_MAX
net.netfilter.nf_conntrack_tcp_timeout_established = 600
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 30
net.netfilter.nf_conntrack_generic_timeout = 60
net.netfilter.nf_conntrack_tcp_loose = 1
net.netfilter.nf_conntrack_tcp_be_liberal = 1
net.netfilter.nf_conntrack_tcp_max_retrans = 3
net.netfilter.nf_conntrack_buckets = $(($CONNTRACK_MAX / 4))

# ============ 文件句柄限制 ============
fs.file-max = 2097152
fs.nr_open = 2097152
EOF

  # 设置TCP初始拥塞窗口 (如果内核支持)
[ -f /proc/sys/net/ipv4/tcp_init_cwnd ] && \
    echo "net.ipv4.tcp_init_cwnd=$INIT_CWND" | $USE_SUDO tee -a /etc/sysctl.conf > /dev/null

  # 应用配置
  $USE_SUDO sysctl -p

  # 设置文件描述符限制
  echo "设置文件描述符限制..."
  $USE_SUDO tee -a /etc/security/limits.conf > /dev/null <<EOF
* soft nofile 2097152
* hard nofile 2097152
* soft nproc 2097152  
* hard nproc 2097152
root soft nofile 2097152
root hard nofile 2097152
root soft nproc 2097152
root hard nproc 2097152
EOF

  # 启用IP转发 (对代理服务器重要)
  echo 1 | $USE_SUDO tee /proc/sys/net/ipv4/ip_forward > /dev/null
  echo 1 | $USE_SUDO tee /proc/sys/net/ipv6/conf/all/forwarding > /dev/null

  echo "TCP优化配置已应用完成!"
}

# 多服务器测试结果统计
declare -A SERVER_RESULTS
declare -A SERVER_SCORES
TOTAL_SERVERS=${#IPERF_SERVERS[@]}
SUCCESSFUL_TESTS=0

FINAL_SCORE=0
FINAL_PARAMS=""
BEST_SERVER=""

echo "=== 多服务器测试配置 ==="
echo "测试服务器数量: $TOTAL_SERVERS"
echo "服务器列表: ${IPERF_SERVERS[*]}"

# 预检测服务器连通性
echo "🔍 预检测服务器连通性..."
VALID_SERVERS=()
for server in "${IPERF_SERVERS[@]}"; do
  if ping -c 1 -W 3 "$server" >/dev/null 2>&1; then
    VALID_SERVERS+=("$server")
    echo "  ✅ $server: 可达"
  else
    echo "  ❌ $server: 不可达 (将跳过)"
  fi
done

if [ ${#VALID_SERVERS[@]} -eq 0 ]; then
  echo "❌ 错误：没有可用的测试服务器！"
  exit 1
fi

# 更新服务器列表为有效服务器
IPERF_SERVERS=("${VALID_SERVERS[@]}")
TOTAL_SERVERS=${#IPERF_SERVERS[@]}
echo "有效服务器数量: $TOTAL_SERVERS"
echo "=========================="

for round in {1..3}; do
  echo "第 $round 轮测速..."
  run_speedtest
  
  for server in "${IPERF_SERVERS[@]}"; do
    echo "🔍 测试服务器: $server (第 $round 轮)"
    
    test_tcp_retransmission "$server"
    
    # 根据VPS类型选择不同的参考指标
    case "$VPS_TYPE" in
      relay) 
        # 中转机：优先考虑上行带宽（发送到落地机）
        REF_BW=$UL_SPEED
        # 中转机还需要考虑延迟稳定性
        REF_LATENCY=$PING_RTT
        REF_RETRANS=$RETRANS_RATE
        ;;
      proxy) 
        # 落地机：优先考虑下行带宽（接收网站数据）和延迟
        REF_BW=$DL_SPEED
        REF_LATENCY=$PING_RTT
        REF_RETRANS=$RETRANS_RATE
        ;;
      mixed) 
        # 混合模式：平衡上下行带宽
        REF_BW=$AVG_IPERF
        REF_LATENCY=$PING_RTT
        REF_RETRANS=$RETRANS_RATE
        ;;
    esac
    
    PING_RTT=$(ping_test "$server")
    
    # 确保变量不为空，避免计算错误
    [ -z "$REF_BW" ] && REF_BW=0
    [ -z "$RETRANS_RATE" ] && RETRANS_RATE=0
    [ -z "$PING_RTT" ] && PING_RTT=0
    
    # 跳过异常值和无效数据
    if [ "$REF_BW" -gt 10000 ] || [ "$REF_BW" -eq 0 ]; then
      echo "⚠️  跳过异常值: $server REF_BW=$REF_BW Mbps"
      continue
    fi
    
    # 记录服务器测试结果
    SERVER_RESULTS["$server"]="带宽:${REF_BW}Mbps | RTT:${PING_RTT}ms | 重传:${RETRANS_RATE}% | UL:${UL_SPEED}Mbps | DL:${DL_SPEED}Mbps"
    
    # 根据VPS类型计算不同的得分权重
    case "$VPS_TYPE" in
      relay)
        # 中转机得分：带宽(60%) + 延迟稳定性(30%) + 重传率(10%)
        REF_BW_SCORE=$(echo "scale=0; $REF_BW * 0.6" | bc 2>/dev/null || echo "0")
        PING_SCORE=$(echo "scale=0; $PING_RTT * 3" | bc 2>/dev/null || echo "0")
        RETRANS_SCORE=$(echo "scale=0; $RETRANS_RATE * 5" | bc 2>/dev/null || echo "0")
        if [ "$PING_RTT" -eq 0 ]; then
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        else
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $PING_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        fi
        ;;
      proxy)
        # 落地机得分：延迟(50%) + 带宽(30%) + 重传率(20%)
        REF_BW_SCORE=$(echo "scale=0; $REF_BW * 0.3" | bc 2>/dev/null || echo "0")
        PING_SCORE=$(echo "scale=0; $PING_RTT * 5" | bc 2>/dev/null || echo "0")
        RETRANS_SCORE=$(echo "scale=0; $RETRANS_RATE * 10" | bc 2>/dev/null || echo "0")
        if [ "$PING_RTT" -eq 0 ]; then
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        else
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $PING_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        fi
        ;;
      mixed)
        # 混合模式得分：带宽(40%) + 延迟(40%) + 重传率(20%)
        REF_BW_SCORE=$(echo "scale=0; $REF_BW * 0.4" | bc 2>/dev/null || echo "0")
        PING_SCORE=$(echo "scale=0; $PING_RTT * 4" | bc 2>/dev/null || echo "0")
        RETRANS_SCORE=$(echo "scale=0; $RETRANS_RATE * 8" | bc 2>/dev/null || echo "0")
        if [ "$PING_RTT" -eq 0 ]; then
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        else
          SCORE=$(echo "scale=0; $REF_BW_SCORE - $PING_SCORE - $RETRANS_SCORE" | bc 2>/dev/null || echo "0")
        fi
        ;;
    esac
    
    SERVER_SCORES["$server"]=$SCORE
    SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    
    # 显示不同VPS类型的得分计算方式
    case "$VPS_TYPE" in
      relay)
        echo "📊 $server 得分: $SCORE (中转机权重: 带宽60% + 延迟30% + 重传10%)"
        echo "   得分计算详情: REF_BW=${REF_BW}*0.6=${REF_BW_SCORE}, PING_RTT=${PING_RTT}*3=${PING_SCORE}, RETRANS_RATE=${RETRANS_RATE}*5=${RETRANS_SCORE}"
        echo "   最终计算: ${REF_BW_SCORE} - ${PING_SCORE} - ${RETRANS_SCORE} = $SCORE"
        ;;
      proxy)
        echo "📊 $server 得分: $SCORE (落地机权重: 延迟50% + 带宽30% + 重传20%)"
        echo "   得分计算详情: REF_BW=${REF_BW}*0.3=${REF_BW_SCORE}, PING_RTT=${PING_RTT}*5=${PING_SCORE}, RETRANS_RATE=${RETRANS_RATE}*10=${RETRANS_SCORE}"
        echo "   最终计算: ${REF_BW_SCORE} - ${PING_SCORE} - ${RETRANS_SCORE} = $SCORE"
        ;;
      mixed)
        echo "📊 $server 得分: $SCORE (混合模式权重: 带宽40% + 延迟40% + 重传20%)"
        echo "   得分计算详情: REF_BW=${REF_BW}*0.4=${REF_BW_SCORE}, PING_RTT=${PING_RTT}*4=${PING_SCORE}, RETRANS_RATE=${RETRANS_RATE}*8=${RETRANS_SCORE}"
        echo "   最终计算: ${REF_BW_SCORE} - ${PING_SCORE} - ${RETRANS_SCORE} = $SCORE"
        ;;
    esac
    
    adjust_tcp "$REF_BW" "$RETRANS_RATE" "$PING_RTT" "$round"
    
    # 根据VPS类型选择最佳配置策略
    case "$VPS_TYPE" in
      relay)
        # 中转机：选择平均性能最好的配置，而不是单一服务器最优
        # 这里先记录所有配置，最后选择平均性能最好的
        if [ -z "$RELAY_CONFIGS" ]; then
          RELAY_CONFIGS="$server|${REF_BW}|${PING_RTT}|${RETRANS_RATE}|$BUFFER|$INIT_CWND|$TIMEOUT|$CONGESTION|$QDISC"
        else
          RELAY_CONFIGS="$RELAY_CONFIGS;$server|${REF_BW}|${PING_RTT}|${RETRANS_RATE}|$BUFFER|$INIT_CWND|$TIMEOUT|$CONGESTION|$QDISC"
        fi
        # 暂时选择得分最高的作为参考
        if compare_float "$SCORE" ">" "$FINAL_SCORE"; then
          FINAL_SCORE=$SCORE
          BEST_SERVER=$server
          FINAL_PARAMS="服务器: $server | 模式: $VPS_TYPE | 带宽: ${REF_BW}Mbps | RTT: ${PING_RTT}ms | 重传: ${RETRANS_RATE}% | 缓冲: $BUFFER | cwnd: $INIT_CWND | timeout: $TIMEOUT | 拥塞: $CONGESTION | 调度器: $QDISC | CPU: ${CPU_CORES}核 @${CPU_MHZ}MHz"
        fi
        ;;
      proxy|mixed)
        # 落地机和混合模式：选择单一最优配置
        if compare_float "$SCORE" ">" "$FINAL_SCORE"; then
          FINAL_SCORE=$SCORE
          BEST_SERVER=$server
          FINAL_PARAMS="服务器: $server | 模式: $VPS_TYPE | 带宽: ${REF_BW}Mbps | RTT: ${PING_RTT}ms | 重传: ${RETRANS_RATE}% | 缓冲: $BUFFER | cwnd: $INIT_CWND | timeout: $TIMEOUT | 拥塞: $CONGESTION | 调度器: $QDISC | CPU: ${CPU_CORES}核 @${CPU_MHZ}MHz"
        fi
        ;;
    esac
  done
  
  [ "$round" -lt 3 ] && echo "等待2分钟..." && sleep 120
done

# 中转机特殊处理：选择平均性能最好的配置
if [ "$VPS_TYPE" = "relay" ] && [ -n "$RELAY_CONFIGS" ]; then
  echo "🔄 中转机模式：分析所有落地机性能，选择最优配置..."
  
  # 计算每个配置对所有服务器的平均性能
  best_avg_score=0
  best_config=""
  
  IFS=';' read -ra CONFIGS <<< "$RELAY_CONFIGS"
  for config in "${CONFIGS[@]}"; do
    IFS='|' read -ra PARTS <<< "$config"
    server="${PARTS[0]}"
    bandwidth="${PARTS[1]}"
    rtt="${PARTS[2]}"
    retrans="${PARTS[3]}"
    buffer="${PARTS[4]}"
    cwnd="${PARTS[5]}"
    timeout="${PARTS[6]}"
    congestion="${PARTS[7]}"
    qdisc="${PARTS[8]}"
    
    # 计算这个配置对所有服务器的平均得分
    total_avg_score=0
    valid_count=0
    
    for test_server in "${IPERF_SERVERS[@]}"; do
      if [ -n "${SERVER_RESULTS[$test_server]}" ]; then
        # 使用这个配置的参数重新计算得分
        test_score=$(echo "$bandwidth * 0.6 - $rtt * 3 - $retrans * 5" | bc 2>/dev/null || echo "0")
        total_avg_score=$(echo "$total_avg_score + $test_score" | bc 2>/dev/null || echo "$total_avg_score")
        valid_count=$((valid_count + 1))
      fi
    done
    
    if [ "$valid_count" -gt 0 ]; then
      avg_score=$(echo "$total_avg_score / $valid_count" | bc 2>/dev/null || echo "0")
      if compare_float "$avg_score" ">" "$best_avg_score"; then
        best_avg_score=$avg_score
        best_config="$config"
      fi
    fi
  done
  
  # 使用最佳平均配置
  if [ -n "$best_config" ]; then
    IFS='|' read -ra PARTS <<< "$best_config"
    BEST_SERVER="${PARTS[0]}"
    FINAL_SCORE=$best_avg_score
    FINAL_PARAMS="服务器: ${PARTS[0]} | 模式: $VPS_TYPE | 带宽: ${PARTS[1]}Mbps | RTT: ${PARTS[2]}ms | 重传: ${PARTS[3]}% | 缓冲: ${PARTS[4]} | cwnd: ${PARTS[5]} | timeout: ${PARTS[6]} | 拥塞: ${PARTS[7]} | 调度器: ${PARTS[8]} | CPU: ${CPU_CORES}核 @${CPU_MHZ}MHz"
    echo "✅ 中转机最佳配置：基于所有落地机平均性能选择"
  fi
fi

# 多服务器测试结果汇总
echo -e "\n=== 多服务器测试结果汇总 ==="
echo "测试服务器总数: $TOTAL_SERVERS"
echo "成功测试数量: $SUCCESSFUL_TESTS"
echo "最佳服务器: $BEST_SERVER"
echo "最佳得分: $FINAL_SCORE"

# 计算平均性能统计
if [ "$SUCCESSFUL_TESTS" -gt 0 ]; then
  total_score=0
  total_bandwidth=0
  total_rtt=0
  total_retrans=0
  count=0
  
  for server in "${IPERF_SERVERS[@]}"; do
    if [ -n "${SERVER_RESULTS[$server]}" ]; then
      score=${SERVER_SCORES[$server]}
      # 使用bc处理浮点数运算，避免bash算术运算的浮点数错误
      total_score=$(echo "$total_score + $score" | bc 2>/dev/null || echo "$total_score")
      
      # 提取带宽信息
      bandwidth=$(echo "${SERVER_RESULTS[$server]}" | awk -F'|' '{print $1}' | awk '{print $2}' | sed 's/Mbps//')
      rtt=$(echo "${SERVER_RESULTS[$server]}" | awk -F'|' '{print $2}' | awk '{print $2}' | sed 's/ms//')
      retrans=$(echo "${SERVER_RESULTS[$server]}" | awk -F'|' '{print $3}' | awk '{print $2}' | sed 's/%//')
      
      # 确保提取的值为数字，避免算术运算错误
      bandwidth=$(echo "$bandwidth" | awk '{print int($1)}' 2>/dev/null || echo "0")
      rtt=$(echo "$rtt" | awk '{print int($1)}' 2>/dev/null || echo "0")
      retrans=$(echo "$retrans" | awk '{print int($1)}' 2>/dev/null || echo "0")
      
      total_bandwidth=$((total_bandwidth + bandwidth))
      total_rtt=$((total_rtt + rtt))
      total_retrans=$((total_retrans + retrans))
      count=$((count + 1))
    fi
  done
  
  if [ "$count" -gt 0 ]; then
    # 使用bc处理浮点数除法运算
    avg_score=$(echo "scale=2; $total_score / $count" | bc 2>/dev/null || echo "0")
    avg_bandwidth=$((total_bandwidth / count))
    avg_rtt=$((total_rtt / count))
    avg_retrans=$((total_retrans / count))
    
    echo ""
    echo "📊 平均性能统计:"
    echo "  平均得分: $avg_score"
    echo "  平均带宽: ${avg_bandwidth}Mbps"
    echo "  平均延迟: ${avg_rtt}ms"
    echo "  平均重传率: ${avg_retrans}%"
  fi
fi
echo ""

# 显示所有服务器结果（按得分排序）
echo "📊 各服务器详细结果（按性能排名）:"

# 创建临时文件存储排序数据
TEMP_FILE=$(mktemp)
for server in "${IPERF_SERVERS[@]}"; do
  if [ -n "${SERVER_RESULTS[$server]}" ]; then
    score=${SERVER_SCORES[$server]}
    echo "$score $server ${SERVER_RESULTS[$server]}" >> "$TEMP_FILE"
  fi
done

# 按得分降序排序并显示
if [ -s "$TEMP_FILE" ]; then
  rank=1
  sort -nr "$TEMP_FILE" | while read score server result; do
    if [ "$server" = "$BEST_SERVER" ]; then
      echo "  🏆 第${rank}名: $server: $result | 得分: $score (最佳)"
    else
      echo "  📈 第${rank}名: $server: $result | 得分: $score"
    fi
    rank=$((rank + 1))
  done
else
  echo "  ❌ 没有成功的测试结果"
fi

# 清理临时文件
rm -f "$TEMP_FILE"

echo -e "\n=== 最终优化配置 ==="
case "$VPS_TYPE" in
  relay)
    echo "🔄 中转机优化策略："
    echo "  • 优先考虑上行带宽（发送到落地机）"
    echo "  • 平衡多个落地机的平均性能"
    echo "  • 优化连接稳定性和队列处理能力"
    ;;
  proxy)
    echo "🌐 落地机优化策略："
    echo "  • 优先考虑延迟稳定性（网站交互）"
    echo "  • 优化下行带宽（接收网站数据）"
    echo "  • 注重连接质量和重传率控制"
    ;;
  mixed)
    echo "⚖️  混合模式优化策略："
    echo "  • 平衡上下行带宽需求"
    echo "  • 兼顾中转和落地功能"
    echo "  • 全能配置适应多种场景"
    ;;
esac
echo ""
echo "最佳TCP配置：$FINAL_PARAMS"

# 保存详细结果到文件
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo "=== 多服务器TCP优化测试报告 ===" > ~/tcp_optimization_report_$TIMESTAMP.log
echo "测试时间: $(date)" >> ~/tcp_optimization_report_$TIMESTAMP.log
echo "VPS类型: $VPS_TYPE" >> ~/tcp_optimization_report_$TIMESTAMP.log
echo "测试服务器总数: $TOTAL_SERVERS" >> ~/tcp_optimization_report_$TIMESTAMP.log
echo "成功测试数量: $SUCCESSFUL_TESTS" >> ~/tcp_optimization_report_$TIMESTAMP.log
echo "" >> ~/tcp_optimization_report_$TIMESTAMP.log

echo "各服务器详细结果:" >> ~/tcp_optimization_report_$TIMESTAMP.log
for server in "${IPERF_SERVERS[@]}"; do
  if [ -n "${SERVER_RESULTS[$server]}" ]; then
    score=${SERVER_SCORES[$server]}
    echo "  $server: ${SERVER_RESULTS[$server]} | 得分: $score" >> ~/tcp_optimization_report_$TIMESTAMP.log
  else
    echo "  $server: 测试失败或跳过" >> ~/tcp_optimization_report_$TIMESTAMP.log
  fi
done

echo "" >> ~/tcp_optimization_report_$TIMESTAMP.log
echo "最佳配置: $FINAL_PARAMS" >> ~/tcp_optimization_report_$TIMESTAMP.log

echo -e "\n✅ 详细报告已保存到: ~/tcp_optimization_report_$TIMESTAMP.log"

# 显示完成信息
echo ""
echo "============================================================================="
echo "                    TCPeak.sh 优化完成!"
echo "============================================================================="
echo "✅ TCP参数优化已成功应用"
echo "✅ 系统性能配置已更新"
echo "✅ 多服务器测试已完成"
echo ""
echo "📊 优化摘要:"
echo "  • VPS类型: $VPS_TYPE"
echo "  • 应用场景: $SCENE_NAME"
echo "  • 性能模式: $PERFORMANCE_MODE"
echo "  • 最佳服务器: $BEST_SERVER"
echo "  • 测试报告: ~/tcp_optimization_report_$TIMESTAMP.log"
echo ""
echo "🔄 建议操作:"
echo "  • 重启系统以确保所有参数生效"
echo "  • 运行性能测试验证优化效果"
echo "  • 监控系统稳定性"
echo ""
echo "📞 技术支持:"
echo "  开发者: Libyte"
echo "  版本: 250725"
echo "  脚本: TCPeak.sh"
echo "============================================================================="
