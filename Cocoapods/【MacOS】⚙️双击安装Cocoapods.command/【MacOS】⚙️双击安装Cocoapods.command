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
  # ================================== Jobs CocoaPods Installer ==================================
  # - macOS 双击运行（.command）友好
  # - 自动安装/注入 Homebrew 环境
  # - fzf：无则安装，有则可选升级（回车跳过，输入任意字符升级）
  # - Ruby：默认使用 Homebrew Ruby，避免系统 Ruby 权限/版本问题
  # - CocoaPods：默认用 Homebrew 安装（最稳），失败再 fallback 到 gem（配合 brew ruby）
  # - 全流程日志：/tmp/${SCRIPT_BASENAME}.log
  # ==============================================================================================

  set -e

  # ================================== 全局变量 ==================================
  START_TIME=$(date +%s)
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

  # ================================== 日志与彩色输出 ==================================
  log() { echo -e "$1" | tee -a "$LOG_FILE"; }

  # 你原脚本里用到了 _color_echo，这里补齐，并且写入 LOG_FILE
  _color_echo() {
    local color="$1"; shift
    local text="$*"

    case "$color" in
      red)        log "\033[31m${text}\033[0m" ;;
      green)      log "\033[32m${text}\033[0m" ;;
      yellow)     log "\033[33m${text}\033[0m" ;;
      blue)       log "\033[34m${text}\033[0m" ;;
      purple)     log "\033[35m${text}\033[0m" ;;
      cyan)       log "\033[36m${text}\033[0m" ;;
      white)      log "\033[37m${text}\033[0m" ;;
      gray)       log "\033[90m${text}\033[0m" ;;

      bold)       log "\033[1m${text}\033[0m" ;;
      underline)  log "\033[4m${text}\033[0m" ;;

      success)    log "\033[1;32m✔ ${text}\033[0m" ;;
      error)      log "\033[1;31m✖ ${text}\033[0m" ;;
      info)       log "\033[1;34mℹ ${text}\033[0m" ;;
      warning)    log "\033[1;33m⚠ ${text}\033[0m" ;;
      note)       log "\033[1;35m➤ ${text}\033[0m" ;;

      *)          log "${text}" ;;
    esac
  }

  info_echo()      { _color_echo info "$1"; }
  success_echo()   { _color_echo success "$1"; }
  warn_echo()      { _color_echo warning "$1"; }
  note_echo()      { _color_echo note "$1"; }
  error_echo()     { _color_echo error "$1"; }
  gray_echo()      { _color_echo gray "$1"; }
  bold_echo()      { _color_echo bold "$1"; }

  # ================================== UI / 工具函数 ==================================
  print_logo() {
    _color_echo cyan "======================="
    _color_echo cyan "     Jobs Installer    "
    _color_echo cyan "======================="
    gray_echo "日志：$LOG_FILE"
  }

  print_duration() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    info_echo "⚙️ 脚本总耗时：${duration}s"
  }

  pause_to_exit() {
    echo ""
    note_echo "✅ 脚本结束。按回车退出..."
    IFS= read -r _
  }
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }

  confirm_upgrade() {
    # 回车：跳过；输入任意字符：执行升级（按你的要求）
    local what="$1"
    info_echo "🔄 检测到 ${what} 已安装。"
    echo "👉 回车：跳过升级"
    echo "👉 输入任意字符后回车：执行升级"
    local confirm
    IFS= read -r confirm
    [[ -n "$confirm" ]]
  }

  ensure_command() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
      error_echo "❌ 缺少命令：$cmd"
      [[ -n "$hint" ]] && note_echo "$hint"
      return 1
    fi
  }

  # ================================== Xcode Command Line Tools ==================================
  ensure_clt() {
    if xcode-select -p &>/dev/null; then
      success_echo "✅ Xcode Command Line Tools 已安装"
      return 0
    fi

    warn_echo "⚠️ 未检测到 Xcode Command Line Tools（Homebrew 需要它）"
    note_echo "将尝试触发安装：会弹出系统安装窗口，按提示完成后重新运行脚本。"
    xcode-select --install || true

    pause_to_exit
    exit 1
  }

  # ================================== Homebrew ==================================
  detect_brew_bin() {
    if command -v brew &>/dev/null; then
      command -v brew
      return 0
    fi

    # Finder 双击运行时经常 PATH 不完整：这里兜底
    if [[ -x /opt/homebrew/bin/brew ]]; then
      echo /opt/homebrew/bin/brew
      return 0
    fi

    if [[ -x /usr/local/bin/brew ]]; then
      echo /usr/local/bin/brew
      return 0
    fi

    return 1
  }

  apply_brew_shellenv() {
    local brew_bin="$1"
    eval "$("$brew_bin" shellenv)"
  }
  install_homebrew() {
    local arch="$(get_cpu_arch)"
    local shell_name="${SHELL##*/}"
    local profile_file=""
    local brew_bin=""

    if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
      warn_echo "未检测到 Homebrew，准备安装（架构：$arch）"
      if [[ "$arch" == "arm64" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
        brew_bin="/opt/homebrew/bin/brew"
      else
        arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
        brew_bin="/usr/local/bin/brew"
      fi
      success_echo "Homebrew 安装完成"
    else
      command -v brew >/dev/null 2>&1 && brew_bin="$(command -v brew)"
      [[ -z "$brew_bin" && -x "/opt/homebrew/bin/brew" ]] && brew_bin="/opt/homebrew/bin/brew"
      [[ -z "$brew_bin" && -x "/usr/local/bin/brew" ]] && brew_bin="/usr/local/bin/brew"
    fi

    case "$shell_name" in
      zsh) profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *) profile_file="$HOME/.profile" ;;
    esac
    inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
    eval "$(${brew_bin} shellenv)" || true

    info_echo "Homebrew 已安装。"
    if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
      brew update  || { error_echo "brew update 失败"; return 1; }
      brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
      brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
      brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
      brew -v      || warn_echo "打印 brew 版本失败，可忽略"
      success_echo "Homebrew 健康更新完成"
    else
      note_echo "已跳过 Homebrew 更新"
    fi
  }

  # ================================== fzf（自检/安装/升级） ==================================
  install_fzf() {
    ensure_command brew "Homebrew 不可用，无法安装 fzf。"

    if ! command -v fzf &>/dev/null; then
      note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
      brew install fzf || { error_echo "❌ fzf 安装失败"; pause_to_exit; exit 1; }
      success_echo "✅ fzf 安装成功：$(fzf --version 2>/dev/null || echo 'unknown')"
      return 0
    fi

    # 已安装：是否升级（回车跳过，任意字符升级）
    if confirm_upgrade "fzf"; then
      info_echo "⏳ 正在升级 fzf..."
      brew upgrade fzf || { error_echo "❌ fzf 升级失败"; return 1; }
      brew cleanup || { warn_echo "⚠️ brew cleanup 执行时有警告"; }
      success_echo "✅ fzf 已升级到最新版本：$(fzf --version 2>/dev/null || echo 'unknown')"
    else
      note_echo "⏭️ 已选择跳过 fzf 升级"
    fi
  }

  # ================================== Ruby（优先 Homebrew Ruby） ==================================
  ensure_brew_ruby() {
    ensure_command brew "Homebrew 不可用，无法安装 Ruby。"

    if brew list --formula ruby &>/dev/null; then
      success_echo "✅ Homebrew Ruby 已安装"
    else
      note_echo "💎 未检测到 Homebrew Ruby，正在安装..."
      brew install ruby || { error_echo "❌ Ruby 安装失败"; pause_to_exit; exit 1; }
      success_echo "✅ Ruby 安装成功"
    fi

    # 当前会话注入 PATH，确保 ruby/gem 指向 brew ruby
    local ruby_prefix
    ruby_prefix="$(brew --prefix ruby 2>/dev/null || true)"
    if [[ -n "$ruby_prefix" && -d "$ruby_prefix/bin" ]]; then
      export PATH="$ruby_prefix/bin:$PATH"
    fi

    info_echo "Ruby: $(ruby -v 2>/dev/null || echo 'not found')"
    info_echo "Gem : $(gem -v 2>/dev/null || echo 'not found')"
  }

  # ================================== RubyGems 源（可选） ==================================
  is_in_china() {
    ensure_command curl "无法访问网络，跳过根据 IP 判断。" || return 1

    local json
    json=$(curl -s --max-time 3 https://ipinfo.io || true)
    [[ -z "$json" ]] && return 1

    if command -v jq &>/dev/null; then
      local country
      country=$(echo "$json" | jq -r '.country' 2>/dev/null || true)
      [[ "$country" == "CN" ]] && return 0 || return 1
    fi

    # 无 jq：用简单 grep 兜底
    echo "$json" | grep -q '"country"[[:space:]]*:[[:space:]]*"CN"'
  }

  set_gem_source() {
    command -v gem &>/dev/null || { warn_echo "⚠️ gem 不可用，跳过 RubyGems 源设置"; return 0; }

    if is_in_china; then
      gem sources --remove https://rubygems.org/ 2>/dev/null || true
      gem sources --add https://gems.ruby-china.com/ 2>/dev/null || true
      note_echo "🇨🇳 检测到可能在中国网络环境：已切换 RubyGems 源为 ruby-china"
    else
      gem sources --remove https://gems.ruby-china.com/ 2>/dev/null || true
      gem sources --add https://rubygems.org/ 2>/dev/null || true
      note_echo "🌐 使用官方 RubyGems 源"
    fi

    info_echo "📦 当前 RubyGems 源列表："
    gem sources -l | tee -a "$LOG_FILE" || true
  }

  # ================================== CocoaPods 安装 ==================================
  install_cocoapods() {
    ensure_command brew "Homebrew 不可用，无法安装 CocoaPods。"

    if command -v pod &>/dev/null; then
      success_echo "✅ CocoaPods 已安装：$(pod --version 2>/dev/null || echo 'unknown')"
      return 0
    fi

    note_echo "📦 正在通过 Homebrew 安装 CocoaPods（推荐/最稳）..."
    brew install cocoapods || {
      warn_echo "⚠️ brew 安装 CocoaPods 失败，尝试改用 gem 安装（使用 Homebrew Ruby）"

      ensure_brew_ruby
      set_gem_source

      gem install cocoapods -N || { error_echo "❌ gem 安装 CocoaPods 失败"; pause_to_exit; exit 1; }
    }

    if ! command -v pod &>/dev/null; then
      # gem 安装后 PATH 可能没更新，尝试修复
      if command -v gem &>/dev/null; then
        local gem_bin
        gem_bin=$(ruby -e 'puts Gem.user_dir' 2>/dev/null)/bin
        [[ -d "$gem_bin" ]] && export PATH="$gem_bin:$PATH"
      fi
    fi

    command -v pod &>/dev/null || { error_echo "❌ CocoaPods 安装后仍未找到 pod 命令"; pause_to_exit; exit 1; }

    success_echo "✅ CocoaPods 安装完成：$(pod --version 2>/dev/null || echo 'unknown')"

    # CocoaPods 现在默认走 CDN，通常不需要 pod setup；这里做首次初始化兜底
    if [[ ! -d "$HOME/.cocoapods" ]]; then
      note_echo "🔧 首次初始化 CocoaPods（可选）：pod setup"
      pod setup || warn_echo "⚠️ pod setup 执行失败（通常不影响使用）"
    else
      gray_echo "ℹ 已存在 ~/.cocoapods，跳过 pod setup"
    fi
  }

  # ================================== 备份配置文件（可选） ==================================
  backup_configs() {
    local files=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bash_profile" "$HOME/.profile")
    for f in "${files[@]}"; do
      [[ -f "$f" ]] || continue
      cp "$f" "$f.bak" 2>/dev/null || true
    done
    success_echo "📦 配置文件已备份（*.bak，如存在）"
  }

  # ================================== 主流程 ==================================
  main() {
    : > "$LOG_FILE" 2>/dev/null || true

    print_logo
    backup_configs

    install_homebrew

    # 你的旧脚本里依赖过 fzf（菜单），所以这里先保证它可用
    install_fzf

    # 解决“新系统 ruby 环境安装失败/系统 ruby 权限问题”
    ensure_brew_ruby

    install_cocoapods

    print_duration
    success_echo "🎉 所有步骤已完成，日志保存在：$LOG_FILE"
  }

  trap 'error_echo "❌ 脚本中途失败，详见日志：$LOG_FILE"; pause_to_exit' ERR

  main "$@"
  pause_to_exit

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
