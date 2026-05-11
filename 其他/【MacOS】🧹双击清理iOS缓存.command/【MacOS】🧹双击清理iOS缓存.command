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
  # ===============================================================
  #  clean_ios_like.command
  # ---------------------------------------------------------------
  #  功能：
  #   • 在项目根目录执行，自动识别 Flutter iOS 或纯 iOS 工程
  #   • 执行常见缓存清理（Pods、DerivedData、Flutter 构建产物等）
  #   • 结构化封装：所有逻辑函数化，main 中统一调用
  #   • 执行前显示自述，并等待用户回车确认；提供 --yes 跳过确认
  # ---------------------------------------------------------------
  #  用法：
  #   • 将脚本放到项目根目录（与 .git 同级），双击或终端执行：
  #     ./clean_ios_like.command            # 正常模式（交互确认）
  #     ./clean_ios_like.command --yes      # 非交互模式（直接执行）
  # ===============================================================

  set -u  # 禁止未定义变量；不使用 -e，避免单点失败直接中断

  # =========================== 输出方法 ===========================
  info()    { echo "📘 $1"; }
  success() { echo "✅ $1"; }
  error()   { echo "❌ $1"; }

  # =========================== 自述页面 ===========================
  show_intro() {
    clear
    cat <<'EOF'
  🧹=================================================
                iOS / Flutter iOS 清理工具
  =================================================
  将清理以下内容（按项目类型自动识别）：

  【iOS 工程】
    • Pods/
    • Podfile.lock
    • Xcode DerivedData（当前用户下）

  【Flutter iOS 工程】
    • ios/Pods
    • ios/Podfile.lock
    • ios/.symlinks
    • ios/Flutter 目录下缓存（App.framework、*.xcframework 等）
    • .dart_tool、build、pubspec.lock
    • Xcode DerivedData（当前用户下）

  ⚠️ 注意：该操作会删除本地缓存与构建产物，请确保已保存修改。
  =================================================
  EOF
  }

  wait_for_enter() {
    read "?👉 按回车键确认继续（或 Ctrl+C 取消）..."
  }

  # =========================== 目录与参数 ===========================
  enter_script_dir() {
    # 强制切到脚本所在目录（项目根）
    local base_dir
    base_dir="$(cd "$(dirname "$0")" && pwd)"
    cd "$base_dir" || { error "无法进入脚本目录：$base_dir"; exit 1; }
    info "📂 当前起点: $base_dir"
  }

  parse_args() {
    # 支持 --yes 跳过确认
    SKIP_CONFIRM="0"
    for arg in "$@"; do
      case "$arg" in
        --yes|-y) SKIP_CONFIRM="1" ;;
      esac
    done
  }

  confirm_or_exit() {
    [[ "$SKIP_CONFIRM" == "1" ]] && return 0
    echo
    read "?⚠️  确认执行清理吗？(y/N): " yn
    case "${yn:l}" in
      y|yes) return 0 ;;
      *) info "已取消。"; exit 0 ;;
    esac
  }

  # =========================== 清理实现 ===========================
  clean_ios() {
    local path="$1"
    cd "$path" || { error "无法进入 $path"; exit 1; }

    info "🧹 正在清理 iOS 缓存目录..."
    rm -rf Pods
    rm -rf Podfile.lock
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
    success "🧽 iOS 缓存清理完成"
  }

  clean_flutter_ios() {
    local path="$1"
    cd "$path" || { error "无法进入 $path"; exit 1; }

    info "🧹 正在清理 Flutter iOS 缓存..."
    rm -rf ios/Pods
    rm -rf ios/Podfile.lock
    rm -rf ios/.symlinks
    rm -rf ios/Flutter/Flutter.podspec
    rm -rf ios/Flutter/App.framework
    rm -rf ios/Flutter/engine
    rm -rf ios/Flutter/*.xcframework
    rm -rf ios/Flutter/Flutter.framework
    rm -rf ios/Flutter/flutter_export_environment.sh
    rm -rf ios/Flutter/Generated.xcconfig
    rm -rf ios/Flutter/ephemeral
    rm -rf .dart_tool
    rm -rf build
    rm -rf pubspec.lock
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
    success "🧽 Flutter iOS 缓存清理完成"
  }

  # =========================== 类型识别 ===========================
  detect_project_type() {
    # 返回：echo "flutter" | "ios" | "unknown"
    if [[ -f "pubspec.yaml" && -d "ios" ]]; then
      echo "flutter"
    elif [[ -f "Podfile" ]]; then
      echo "ios"
    else
      echo "unknown"
    fi
  }

  # =========================== 主函数 ===========================
  main() {
    parse_args "$@"
    show_intro
    wait_for_enter
    enter_script_dir
    confirm_or_exit

    local kind
    kind="$(detect_project_type)"

    case "$kind" in
      flutter)
        info "🧩 检测到 Flutter 工程"
        clean_flutter_ios "$(pwd)"
        ;;
      ios)
        info "📱 检测到 iOS 工程"
        clean_ios "$(pwd)"
        ;;
      *)
        error "无法识别的工程结构，未检测到 Podfile 或 pubspec.yaml"
        exit 1
        ;;
    esac

    success "🎉 全部完成"
  }

  # =========================== 执行入口 ===========================
  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
