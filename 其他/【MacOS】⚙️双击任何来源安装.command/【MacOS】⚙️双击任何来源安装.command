#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️双击任何来源安装.command
# - 核心用途：执行“⚙️双击任何来源安装”对应的本机环境配置任务。
# - 影响范围：可能安装、更新或修改当前用户的工具链与配置文件。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 统一输出终端信息并同步记录日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出 color echo 对应级别的日志信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出 err echo 对应级别的日志信息。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出 underline echo 对应级别的日志信息。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs path 对应的独立处理逻辑。
abs_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="${p//\"/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P)
  elif [[ -f "$p" ]]; then
    (cd "${p:h}" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "${p:t}")
  else
    return 1
  fi
}
# 收集并校验 ask run 对应的用户确认。
ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验 confirm yes 对应的用户确认。
confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject shellenv block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local header="# >>> Homebrew 环境变量 >>>"
  [[ -z "$profile_file" || -z "$shellenv_cmd" ]] && { error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"; return 1; }
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv_cmd" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew shellenv：$profile_file"
  elif grep -Fq "$header" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew 环境变量块：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv_cmd"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi
  eval "$shellenv_cmd" || true
}
# 封装 activate homebrew shellenv 对应的独立处理逻辑。
activate_homebrew_shellenv() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""
  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ "$arch" == "arm64" && -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi
  [[ -z "$brew_bin" ]] && return 1

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
  eval "$(${brew_bin} shellenv)"
}
# 执行 run brew health update 对应的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 准备并配置 install homebrew 对应的运行条件。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""

  if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="/usr/local/bin/brew"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || true
    return 0
  fi

  activate_homebrew_shellenv || true
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 封装 brew install or upgrade 对应的独立处理逻辑。
brew_install_or_upgrade() {
  local formula="$1"
  [[ -z "$formula" ]] && return 1
  install_homebrew || return 1
  if ! brew list --formula "$formula" >/dev/null 2>&1 && ! command -v "$formula" >/dev/null 2>&1; then
    note_echo "未检测到 $formula，正在安装..."
    brew install "$formula" || { error_echo "$formula 安装失败"; return 1; }
    success_echo "$formula 安装完成"
  else
    info_echo "$formula 已安装。"
    if ask_run "是否升级 $formula？"; then
      brew upgrade "$formula" || warn_echo "$formula 可能已是最新或升级失败，请检查输出"
      brew cleanup || true
    else
      note_echo "已跳过 $formula 升级"
    fi
  fi
}
# 输出 show readme and wait 对应的说明与结果。
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】⚙️双击任何来源安装.command'
  print -r -- '核心用途：执行“⚙️双击任何来源安装”对应的本机环境配置任务。'
  print -r -- '影响范围：可能安装、更新或修改当前用户的工具链与配置文件。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行 run original logic 对应的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ✅ 彩色输出函数
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
  # 统一输出终端信息并同步记录日志。
  log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
  # 输出 color echo 对应级别的日志信息。
  color_echo()     { log "\033[1;32m$1\033[0m"; }        # ✅ 正常绿色输出
  # 输出 info echo 对应级别的日志信息。
  info_echo()      { log "\033[1;34mℹ $1\033[0m"; }      # ℹ 信息
  # 输出 success echo 对应级别的日志信息。
  success_echo()   { log "\033[1;32m✔ $1\033[0m"; }      # ✔ 成功
  # 输出 warn echo 对应级别的日志信息。
  warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }      # ⚠ 警告
  # 输出 warm echo 对应级别的日志信息。
  warm_echo()      { log "\033[1;33m$1\033[0m"; }        # 🟡 温馨提示（无图标）
  # 输出 note echo 对应级别的日志信息。
  note_echo()      { log "\033[1;35m➤ $1\033[0m"; }      # ➤ 说明
  # 输出 error echo 对应级别的日志信息。
  error_echo()     { log "\033[1;31m✖ $1\033[0m"; }      # ✖ 错误
  # 输出 err echo 对应级别的日志信息。
  err_echo()       { log "\033[1;31m$1\033[0m"; }        # 🔴 错误纯文本
  # 输出 debug echo 对应级别的日志信息。
  debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }     # 🐞 调试
  # 输出 highlight echo 对应级别的日志信息。
  highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }     # 🔹 高亮
  # 输出 gray echo 对应级别的日志信息。
  gray_echo()      { log "\033[0;90m$1\033[0m"; }        # ⚫ 次要信息
  # 输出 bold echo 对应级别的日志信息。
  bold_echo()      { log "\033[1m$1\033[0m"; }           # 📝 加粗
  # 输出 underline echo 对应级别的日志信息。
  underline_echo() { log "\033[4m$1\033[0m"; }           # 🔗 下划线
  # ✅ 自述信息
  print_intro() {
    echo ""
    info_echo  "=============================="
    info_echo  "   Jobs Gatekeeper 解锁器 🛡️ "
    info_echo  "=============================="
    echo ""
    info_echo "📌 本脚本用于启用 macOS 的『任何来源』安装权限。"
    echo ""
    warn_echo "⚠ macOS 13+ 需先关闭 SIP（系统完整性保护）后才能启用。"
    echo ""
    success_echo "✔ 如果你尚未关闭 SIP，请重启进入『恢复模式』执行："
    echo "   csrutil disable"
    echo ""
    gray_echo "✅ 验证方式：正常进入系统后，终端执行：csrutil status"
    gray_echo "👉 应输出：System Integrity Protection status: disabled."
    echo ""
  }
  # ✅  用户确认继续执行
  wait_for_confirmation() {
    read "?⏳ 按下回车继续执行脚本（将先检查是否已关闭 SIP）..."
  }
  # ✅ 检查 SIP 状态
  check_sip_status() {
    SIP_STATUS=$(csrutil status 2>/dev/null)
    if [[ "$SIP_STATUS" != *"disabled"* ]]; then
      error_echo "❌ 当前 SIP 尚未关闭，不能启用『任何来源』。"
      echo ""
      warn_echo "请根据提示进入恢复模式，执行：csrutil disable 后再运行本脚本。"
      echo ""
      exit 1
    fi
    success_echo "✅ 检测通过，SIP 已关闭"
  }
  # ✅ 启用“任何来源”权限
  enable_anywhere_permission() {
    info_echo "🔧 正在启用『任何来源』安装权限..."
    echo ""
    sudo spctl --master-disable
  }
  # ✅ 打开系统设置
  open_system_setting() {
    echo ""
    success_echo "✅ 命令执行完毕。请前往：系统设置 > 隐私与安全性"
    info_echo    "👉 向下滚动，点击「允许来自任何来源」确认该设置。"
    echo ""
    read "?⏳ 按下回车后将自动打开系统设置..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy"
    echo ""
    info_echo "🍎 完成！确认设置后，你即可安装任何第三方来源软件。"
  }
  # ✅ 主函数
  main() {
    clear                                      # 🧹 清空终端界面，保持输出整洁
    print_intro                                # 🖨️ 自述信息
    wait_for_confirmation                      # ⏸️ 等待用户回车确认继续执行
    check_sip_status                           # ✅ 检查是否已关闭 SIP（系统完整性保护）
    enable_anywhere_permission                 # 🔓 启用「任何来源」安装权限
    open_system_setting                        # ⚙️ 打开系统设置供用户确认
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
