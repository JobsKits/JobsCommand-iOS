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
  # ✅ 日志与输出函数
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

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

  # ✅ 自述信息
  show_intro() {
    echo ""
    success_echo "📜 脚本用途说明"
    gray_echo "--------------------------------------------"
    info_echo  "1️⃣ 自动检测并安装 brew 与 fzf 工具（如未安装）"
    info_echo  "2️⃣ 通过 fzf 选择要打开的配置文件，支持多选"
    info_echo  "3️⃣ 默认回车代表“全部文件”，可按需选择"
    info_echo  "4️⃣ 自动打开文件，并自动执行 source 加载"
    gray_echo "--------------------------------------------"
    echo ""
    read "?👉 按回车开始，输入任意字符退出： " go
    if [[ -n "$go" ]]; then
      error_echo "❌ 用户取消执行，已退出。"
      exit 0
    fi
  }

  # ✅ 工具检测模块 🧰
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }

  check_and_install_brew() {
    arch=$(get_cpu_arch)
    if ! command -v brew &>/dev/null; then
      _color_echo yellow "🧩 未检测到 Homebrew，正在安装 ($arch)..."
      if [[ "$arch" == "arm64" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
          _color_echo red "❌ Homebrew 安装失败"
          exit 1
        }
      else
        arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
          _color_echo red "❌ Homebrew 安装失败（x86_64）"
          exit 1
        }
      fi
      _color_echo green "✅ Homebrew 安装成功"
    else
      _color_echo blue "🔄 Homebrew 已安装，更新中..."
      ask_run "执行 Homebrew 更新 / 升级 / 清理？" && run_brew_health_update
      _color_echo green "✅ Homebrew 已更新"
    fi
  }

  check_and_install_fzf() {
    if ! command -v fzf &>/dev/null; then
      method=$(fzf_select "通过 Homebrew 安装" "通过 Git 安装")
      case $method in
        *Homebrew*) brew install fzf;;
        *Git*)
          git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install --all
          ;;
        *) err "❌ 取消安装 fzf";;
      esac
    else
      _color_echo blue "🔄 fzf 已安装，升级中..."
      ask_run "升级 fzf？" && brew upgrade fzf
      _color_echo green "✅ fzf 已是最新版"
    fi
  }

  # ✅ 配置文件加载模块 📂
  source_if_exists() {
    local file="$1"
    [[ -s "$file" ]] && source "$file"
  }

  select_config_files() {
    CONFIG_FILES=()
    [[ -f "$HOME/.bash_profile" ]] && CONFIG_FILES+=("$HOME/.bash_profile")
    [[ -f "$HOME/.bashrc"       ]] && CONFIG_FILES+=("$HOME/.bashrc")
    [[ -f "$HOME/.zshrc"        ]] && CONFIG_FILES+=("$HOME/.zshrc")
    [[ -f "$ZSH/oh-my-zsh.sh"   ]] && CONFIG_FILES+=("$ZSH/oh-my-zsh.sh")

    if (( ${#CONFIG_FILES[@]} == 0 )); then
      error_echo "❌ 未检测到任何 shell 配置文件，终止执行"
      exit 1
    fi

    note_echo "👇 请选择你要打开的配置文件（支持多选，默认回车 = 全部）"
    SELECTED_FILES=("${(@f)$(printf '%s\n' "${CONFIG_FILES[@]}" | fzf --multi --prompt "配置文件 > ")}")
    [[ -z "$SELECTED_FILES" ]] && SELECTED_FILES=("${CONFIG_FILES[@]}")
  }

  open_and_source_files() {
    for file in "${SELECTED_FILES[@]}"; do
      highlight_echo "🚀 正在打开并加载：$file"
      open "$file"
      source_if_exists "$file"
    done
  }

  # ✅ 主函数入口 🚀
  main() {
    show_intro                             # ✅ 自述信息
    check_and_install_brew                 # ✅ 自动检测并安装 Homebrew
    check_and_install_fzf                  # ✅ 自动检测并安装 Homebrew.fzf
    select_config_files                    # ✅ 使用 Homebrew.fzf 选择要打开的配置文件
    open_and_source_files                  # ✅ 打开并执行 source 加载
  }

  main "$@"

  # ~/.bash_profile
  # ~/.bashrc
  # ~/.zshrc 是不同的 shell 配置文件，每个文件的优先级和作用取决于你使用的 shell 类型以及你在启动 shell 时的方式
  # 以下是对它们的优先级和作用的详细说明：

  # Bash Shell
  # ~/.bash_profile
  # 这是一个用户级的启动文件，当以登录方式启动 Bash shell 时（例如通过终端登录或者 SSH 登录时），Bash 会读取并执行 ~/.bash_profile 中的内容。
  # 如果 ~/.bash_profile 不存在，Bash 会尝试读取 ~/.bash_login 或者 ~/.profile。

  # ~/.bashrc
  # 这是一个用户级的非登录 shell 启动文件，当启动一个非登录的 Bash shell 时（例如打开一个终端窗口或者执行一个新的 shell 命令时），Bash 会读取并执行 ~/.bashrc 中的内容。
  # 通常在 ~/.bash_profile 中会有一行代码来手动加载 ~/.bashrc，以便确保登录 shell 和非登录 shell 都会执行 ~/.bashrc 中的配置。

  # bash
  # 复制下列代码
  # if [ -f ~/.bashrc ]; then
  #    source ~/.bashrc
  # fi

  # Zsh Shell
  # ~/.zshrc
  # 这是 Zsh 的配置文件，不论是登录 shell 还是非登录 shell，Zsh 启动时都会读取并执行 ~/.zshrc 中的内容。
  # 对于 Zsh 而言，~/.zshrc 是主要的配置文件。

  # 优先级总结
  # 对于 Bash：
  # 登录 shell：先执行 ~/.bash_profile，如果在 ~/.bash_profile 中有 source ~/.bashrc，则会接着执行 ~/.bashrc。
  # 非登录 shell：只执行 ~/.bashrc。

  # 对于 Zsh：
  # 无论是登录 shell 还是非登录 shell，都只执行 ~/.zshrc。
  # 根据你使用的 shell 类型和启动方式，这些文件的优先级和作用会有所不同。
  # 对于大多数桌面用户来说，通常会配置 ~/.bashrc 或者 ~/.zshrc 来设置常用的环境变量和别名，而 ~/.bash_profile 则用来进行一些需要在登录时执行的初始化操作。

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
