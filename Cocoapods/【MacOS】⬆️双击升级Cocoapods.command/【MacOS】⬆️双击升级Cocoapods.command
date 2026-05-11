#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}

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

ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}

confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

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

run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}

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

show_readme_and_wait() {
  clear
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}

run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ✅ 彩色输出函数 🌈
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径

  log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
  color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
  info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
  success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
  warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
  warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
  note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
  error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
  err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
  debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
  highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
  gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
  bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
  underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

  # ✅ 自述信息
  print_usage() {
    success_echo "🛠️ CocoaPods 环境升级助手"
    echo "===================================================================="
    note_echo "1️⃣ 检查当前 Ruby 与 gem 环境"
    note_echo "2️⃣ 检查已安装的 CocoaPods 版本"
    note_echo "3️⃣ 如果非最新，则卸载所有旧版本并安装最新版本"
    note_echo "4️⃣ 验证 pod 命令路径，确保配置生效"
    echo "===================================================================="
    echo ""
    read "?👉 按下回车继续执行，或 Ctrl+C 取消..."
  }

  # ✅ 检查当前 CocoaPods 版本
  check_current_pod_version() {
    if command -v pod &>/dev/null; then
      CURRENT_VERSION=$(pod --version)
      success_echo "当前 pod 版本：$CURRENT_VERSION"
    else
      error_echo "未检测到 pod 命令，可能未安装或环境异常"
      CURRENT_VERSION="none"
    fi
  }

  # ✅ 获取最新版本 🔍
  get_latest_version() {
    LATEST_VERSION=$(gem list -r ^cocoapods$ | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)
    info_echo "远程可用最新版：$LATEST_VERSION"
  }

  # ✅ 检查 Ruby 与 gem 环境 🔧
  check_ruby_env() {
    RUBY_PATH=$(rbenv which ruby 2>/dev/null)
    GEM_HOME=$(gem env home)
    gray_echo "当前 Ruby 路径：$RUBY_PATH"
    gray_echo "当前 gem 安装路径：$GEM_HOME"
  }

  # ✅ 卸载全部 CocoaPods 🧹
  remove_all_cocoapods() {
    warn_echo "卸载所有已安装的 CocoaPods..."
    gem list --local cocoapods | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | while read -r ver; do
      warn_echo "正在卸载版本 $ver ..."
      sudo gem uninstall cocoapods -v "$ver" -aIx
    done
  }

  # ✅ 安装最新 CocoaPods 📦
  install_latest_cocoapods() {
    info_echo "正在安装 CocoaPods $LATEST_VERSION..."
    sudo gem install cocoapods -v "$LATEST_VERSION"
  }

  # ✅ 刷新环境缓存 🔁
  refresh_env() {
    gray_echo "刷新环境缓存中..."
    hash -r
    if command -v rbenv &>/dev/null; then
      gray_echo "rbenv 环境下，执行 rehash ..."
      rbenv rehash
    fi
  }

  # ✅ 查看 pod 路径 🔍
  check_pod_location() {
    POD_PATH=$(which pod)
    success_echo "当前 pod 命令路径：$POD_PATH"
  }

  # ✅ 升级判断与处理 ♻️
  upgrade_if_needed() {
    # ✅ 判断是否为最新版
    if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
      success_echo "✔ 当前已是最新版本，无需升级"
    else
      remove_all_cocoapods                      # ✅ 清空旧版本 🧹 
      install_latest_cocoapods                  # ✅ 安装新版本 📦
      refresh_env                               # ✅ 刷新环境 🔁
      check_current_pod_version                 # ✅ 再次确认：检查当前 CocoaPods 版本
      success_echo "🎉 升级完成，当前版本为：$(pod --version)"
    fi
  }

  # ✅ 主函数入口 🚀
  main() {
    print_usage                                 # ✅ 自述信息 🖨️
    info_echo "🚀 CocoaPods 升级脚本开始执行..."
    check_ruby_env                              # ✅ 检查 Ruby 与 gem 环境 🔧
    check_current_pod_version                   # ✅ 获取当前版本：检查当前 CocoaPods 版本 🧪
    get_latest_version                          # ✅ 获取远程版本 🔍
    upgrade_if_needed                           # ✅ 判断是否为最新版 ♻️
    check_pod_location                          # ✅ 打印 pod 命令路径 🔍
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
