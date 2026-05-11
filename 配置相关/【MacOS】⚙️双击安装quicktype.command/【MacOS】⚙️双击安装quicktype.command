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
  # ================================== 日志与输出函数 ==================================
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

  # ================================== 写入 Homebrew shellenv ==================================
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

  # ================================== 判断芯片架构（ARM64 / x86_64） ==================================
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }

  # ================================== 自检安装 Homebrew（原逻辑） ==================================
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

  # ================================== 自检安装 fzf（原逻辑） ==================================
  install_fzf() {
      if ! command -v fzf &>/dev/null; then
          warn_echo "🧩 未检测到 fzf，正在通过 Homebrew 安装..."
          brew install fzf || {
              error_echo "❌ fzf 安装失败，请手动检查 Homebrew"
              return 1
          }
          success_echo "✅ fzf 安装完成"
      else
          info_echo "✅ fzf 已安装"
      fi
  }

  # ================================== 自述说明 ==================================
  print_readme() {
      bold_echo "🚀 Quicktype 自动安装 / 升级脚本"
      echo
      note_echo "本脚本将执行以下操作："
      gray_echo "  1) 检查并安装 / 更新 Homebrew"
      gray_echo "  2) 使用 Homebrew 检查并安装 / 升级 Node.js + npm"
      gray_echo "  3) 使用 Homebrew 检查并安装 / 升级 fzf"
      gray_echo "  4) 使用 npm 全局安装 / 升级 quicktype"
      gray_echo "  5) 完成后打印 quicktype 版本号"
      echo
      warm_echo "⚠ 过程中可能会请求 sudo 密码（用于 npm 全局安装 / 升级 quicktype）"
      echo
      read -r -p "👉 按回车继续执行，或 Ctrl + C 取消..." _
  }

  # ================================== Homebrew 安装 & 升级封装 ==================================
  ensure_homebrew_and_upgrade() {
      install_homebrew

      if ! command -v brew &>/dev/null; then
          error_echo "❌ 未检测到 Homebrew，后续步骤无法继续"
          exit 1
      fi

      info_echo "🔄 正在更新 Homebrew 仓库..."
      brew update || warn_echo "⚠ Homebrew 更新失败，可稍后手动执行：brew update"

      info_echo "⬆ 正在升级已安装的 Homebrew 包（可能耗时较长）..."
      brew upgrade || warn_echo "⚠ Homebrew 升级过程中有错误，可稍后手动执行：brew upgrade"
  }

  # ================================== Node.js & npm 管理 ==================================
  ensure_node_and_npm() {
      if brew list --versions node &>/dev/null; then
          info_echo "✅ 检测到通过 Homebrew 安装的 Node.js，尝试升级..."
          brew upgrade node || warn_echo "⚠ Node.js 升级失败，可稍后手动执行：brew upgrade node"
      else
          warn_echo "🧩 未检测到 Homebrew 管理的 Node.js，正在通过 Homebrew 安装 node（包含 npm）..."
          brew install node || {
              error_echo "❌ Node.js 安装失败，请检查 Homebrew 或网络"
              exit 1
          }
          success_echo "✅ Node.js 安装完成"
      fi

      info_echo "🔹 当前 Node.js 版本：$(node -v 2>/dev/null || echo '未检测到')"
      info_echo "🔹 当前 npm 版本：$(npm -v 2>/dev/null || echo '未检测到')"
  }

  # ================================== fzf 安装 & 升级封装 ==================================
  ensure_fzf_with_upgrade() {
      if brew list --versions fzf &>/dev/null; then
          info_echo "✅ 检测到通过 Homebrew 安装的 fzf，尝试升级..."
          brew upgrade fzf || warn_echo "⚠ fzf 升级失败，可稍后手动执行：brew upgrade fzf"
      else
          install_fzf
      fi
  }

  # ================================== quicktype 安装 & 升级 ==================================
  ensure_quicktype() {
      if ! command -v npm &>/dev/null; then
          error_echo "❌ 未检测到 npm，无法安装 quicktype，请先确保 Node.js 环境正常"
          exit 1
      fi

      if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
          info_echo "✅ 检测到全局 quicktype，正在通过 npm 升级..."
          sudo npm update -g quicktype || {
              error_echo "❌ quicktype 升级失败，你可以稍后手动执行：sudo npm update -g quicktype"
              return 1
          }
          success_echo "✅ quicktype 已升级到最新版本"
      else
          warn_echo "🧩 未检测到全局 quicktype，正在通过 npm 安装..."
          sudo npm install -g quicktype || {
              error_echo "❌ quicktype 安装失败，你可以稍后手动执行：sudo npm install -g quicktype"
              return 1
          }
          success_echo "✅ quicktype 安装完成"
      fi
  }

  # ================================== 打印 quicktype 版本 ==================================
  show_quicktype_version() {
      if command -v quicktype &>/dev/null; then
          local ver
          ver="$(quicktype --version 2>&1)"
          highlight_echo "🔹 当前 quicktype 版本：${ver}"
      else
          error_echo "❌ 未能检测到 quicktype 命令，请检查 npm 全局路径或重新安装"
      fi
  }

  # ================================== main 入口 ==================================
  main() {
      print_readme
      ensure_homebrew_and_upgrade
      ensure_node_and_npm
      ensure_fzf_with_upgrade
      ensure_quicktype
      show_quicktype_version
      success_echo "🎉 Quicktype 自动安装 / 升级流程已结束"
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
