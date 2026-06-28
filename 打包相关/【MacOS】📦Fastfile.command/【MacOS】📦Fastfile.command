#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📦Fastfile.command
# - 核心用途：执行“📦Fastfile”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs_path 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验用户输入，决定后续执行路径。
confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
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
# 封装 activate_homebrew_shellenv 对应的独立处理逻辑。
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
# 执行已经拆分完成的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 执行对应的环境配置或同步处理。
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
# 封装 brew_install_or_upgrade 对应的独立处理逻辑。
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
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】📦Fastfile.command'
  print -r -- '核心用途：执行“📦Fastfile”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ===============================================================
  #  Jobs Fastlane 初始化脚本（macOS / zsh）
  # ---------------------------------------------------------------
  #  功能：
  #   • 识别 Flutter 工程或原生 iOS 工程
  #   • 安装/更新 Homebrew、fzf、fastlane
  #   • 创建并用所选编辑器打开 Fastfile
  #  交互：
  #   • 启动显示自述，回车确认后继续
  #   • 选择是否创建 Fastfile、选择打开的编辑器
  # ---------------------------------------------------------------
  #  用法：
  #    chmod +x jobs_fastlane_bootstrap.command
  #    ./jobs_fastlane_bootstrap.command
  # ===============================================================

  set -u  # 禁止未定义变量；不启用 -e，关键步骤自行判错
  ########## ✅ 彩色输出 ##########
  _JobsPrint()         { echo "$1$2\033[0m"; }
  # 封装 _JobsPrint_Green 对应的独立处理逻辑。
  _JobsPrint_Green()   { _JobsPrint "\033[1;32m" "$1"; }
  # 封装 _JobsPrint_Red 对应的独立处理逻辑。
  _JobsPrint_Red()     { _JobsPrint "\033[1;31m" "$1"; }
  # 封装 _JobsPrint_Yellow 对应的独立处理逻辑。
  _JobsPrint_Yellow()  { _JobsPrint "\033[1;33m" "$1"; }
  # 封装 _JobsPrint_Blue 对应的独立处理逻辑。
  _JobsPrint_Blue()    { _JobsPrint "\033[1;34m" "$1"; }
  ########## ✅ 自述 ##########
  show_intro() {
    _JobsPrint_Green "🧮 Fastlane 自动配置初始化脚本"
    _JobsPrint_Green "📦 脚本用途："
    _JobsPrint_Green "1️⃣ 自动识别当前是 Flutter 工程还是原生 iOS 工程"
    _JobsPrint_Green "2️⃣ 安装或更新 Homebrew、fzf、fastlane"
    _JobsPrint_Green "3️⃣ 创建并打开 Fastfile 以开始配置自动化流程"
    echo ""
    read "?👉 按下回车键继续执行（Ctrl+C 取消）..."
  }

  ########## ✅ 路径设置 ##########
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  FASTFILE_PATH="$SCRIPT_DIR/fastlane/Fastfile"
  PROJECT_TYPE="unknown"
  ########## ✅ LOGO（可选） ##########
  jobs_logo() {
    _JobsPrint_Green "======== Jobs Fastlane 初始化脚本 ========"
  }
  ########## ✅ 检测工程类型 ##########
  detect_project_type() {
    if [[ -f "$SCRIPT_DIR/pubspec.yaml" && -d "$SCRIPT_DIR/ios" ]]; then
      PROJECT_TYPE="flutter"
      _JobsPrint_Green "🧩 检测到 Flutter 工程"
    elif ls "$SCRIPT_DIR"/*.xcodeproj >/dev/null 2>&1 || ls "$SCRIPT_DIR"/*.xcworkspace >/dev/null 2>&1; then
      PROJECT_TYPE="ios"
      _JobsPrint_Green "📱 检测到原生 iOS 工程"
    else
      PROJECT_TYPE="unknown"
      _JobsPrint_Red "⚠️ 无法识别工程类型（Flutter 或 iOS）"
    fi
  }
  ########## ✅ 写 Homebrew 路径到 Shell Profile ##########
  _configure_brew_path() {
    # 兼容 Intel 与 Apple Silicon
    local brew_bins=(
      "/opt/homebrew/bin"   # Apple Silicon 默认
      "/usr/local/bin"      # Intel 常见
    )
    local path_line_prefix='export PATH="'
    local updated=0
    for b in "${brew_bins[@]}"; do
      if [[ -d "$b" ]]; then
        local line="export PATH=\"$b:\$PATH\""
        for f in ".zshrc" ".bash_profile" ".bashrc"; do
          if [[ -f "$HOME/$f" ]]; then
            grep -qF "$line" "$HOME/$f" 2>/dev/null || { echo "$line" >> "$HOME/$f"; updated=1; }
          else
            echo "$line" >> "$HOME/$f"; updated=1
          fi
        done
      fi
    done
    # 尝试加载
    source "$HOME/.zshrc" 2>/dev/null || true
    source "$HOME/.bashrc" 2>/dev/null || true
    source "$HOME/.bash_profile" 2>/dev/null || true
    (( updated )) && _JobsPrint_Yellow "ℹ️ 已写入 Homebrew PATH 到 shell 配置文件"
  }
  ########## ✅ 安装 Homebrew ##########
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
  # 检查当前运行条件是否满足后续流程要求。
  check_homebrew() {
    if ! command -v brew &>/dev/null; then
      _JobsPrint_Yellow "🍺 未检测到 Homebrew，开始安装..."
      install_homebrew || return 1
    else
      _JobsPrint_Green "✅ Homebrew 已安装"
      brew update || true
      brew upgrade || true
      brew cleanup || true
    fi
    return 0
  }
  ########## ✅ 安装 fzf ##########
  install_fzf() {
    _JobsPrint_Yellow "🔧 安装 fzf..."
    brew install fzf || return 1
    # 安装交互按键绑定脚本（静默）
    if [[ -x "/opt/homebrew/opt/fzf/install" ]]; then
      /opt/homebrew/opt/fzf/install --key-bindings --completion --no-bash --no-fish --no-update-rc >/dev/null 2>&1 || true
    elif [[ -x "$HOME/.fzf/install" ]]; then
      "$HOME/.fzf/install" --key-bindings --completion --no-bash --no-fish --no-update-rc >/dev/null 2>&1 || true
    fi
    _JobsPrint_Green "✅ fzf 安装完成"
    return 0
  }
  # 检查当前运行条件是否满足后续流程要求。
  check_fzf() {
    if ! command -v fzf &>/dev/null; then
      install_fzf || _JobsPrint_Red "⚠️ fzf 安装失败，稍后编辑器选择将使用降级逻辑"
    else
      _JobsPrint_Green "✅ fzf 已安装"
      ask_run "升级 fzf？" && brew upgrade fzf || true
    fi
  }
  ########## ✅ 安装 fastlane ##########
  install_fastlane() {
    _JobsPrint_Yellow "🚀 安装 fastlane..."
    brew install fastlane || return 1
    _JobsPrint_Green "✅ fastlane 安装成功"
    return 0
  }
  # 检查当前运行条件是否满足后续流程要求。
  check_fastlane() {
    if ! command -v fastlane &>/dev/null; then
      install_fastlane || _JobsPrint_Red "⚠️ fastlane 安装失败，请手动检查环境"
    else
      _JobsPrint_Green "✅ fastlane 已安装"
      ask_run "升级 fastlane？" && brew upgrade fastlane || true
    fi
  }
  ########## ✅ 选择编辑器并打开 Fastfile ##########
  _select_editor_and_open() {
    local target="$1"

    # 候选编辑器与可执行命令的映射
    local options=("Xcode" "VSCode" "Android Studio")
    local selection=""

    if command -v fzf >/dev/null 2>&1; then
      selection=$(printf "%s\n" "${options[@]}" | fzf --prompt="🎨 选择编辑器: " --height=10 --reverse) || selection=""
    fi

    # fzf 不可用或用户取消 → 交互降级
    if [[ -z "$selection" ]]; then
      _JobsPrint_Yellow "⚠️ 未选择或缺少 fzf，将尝试使用可用编辑器打开（优先级：VSCode > Xcode > Android Studio）"
      if command -v code >/dev/null 2>&1; then
        selection="VSCode"
      elif open -Ra "Xcode" >/dev/null 2>&1; then
        selection="Xcode"
      elif open -Ra "Android Studio" >/dev/null 2>&1; then
        selection="Android Studio"
      else
        _JobsPrint_Red "❌ 未找到可用编辑器，跳过打开。"
        return 0
      fi
    fi

    case "$selection" in
      "Xcode")           open -a "Xcode" "$target" ;;
      "VSCode")          command -v code >/dev/null 2>&1 && code "$target" || open -a "Visual Studio Code" "$target" ;;
      "Android Studio")  open -a "Android Studio" "$target" ;;
      *)                 _JobsPrint_Yellow "⚠️ 未识别的选择，跳过打开" ;;
    esac
  }
  # 封装 open_fastfile 对应的独立处理逻辑。
  open_fastfile() {
    mkdir -p "$SCRIPT_DIR/fastlane"

    if [[ ! -f "$FASTFILE_PATH" ]]; then
      _JobsPrint_Yellow "📄 未检测到 Fastfile，是否要创建？"
      read "?👉 输入 y 创建，其他键跳过： " init_ans
      if [[ "$init_ans" == "y" ]]; then
        cat > "$FASTFILE_PATH" <<'RUBY'
  # Fastfile initialized by Jobs script
  default_platform(:ios)

  platform :ios do
    desc "Build for beta"
    lane :beta do
      # build_app(scheme: "YourScheme")
    end
  end
RUBY
        _JobsPrint_Green "✅ Fastfile 创建成功: $FASTFILE_PATH"
      fi
    fi

    if [[ -f "$FASTFILE_PATH" ]]; then
      _JobsPrint_Green "🧠 请选择用哪个编辑器打开 Fastfile："
      _select_editor_and_open "$FASTFILE_PATH"
    fi
  }
  ########## ✅ main（统一调用） ##########
  main() {
    cd "$SCRIPT_DIR" || { _JobsPrint_Red "❌ 无法进入脚本目录"; exit 1; }

    show_intro
    jobs_logo
    detect_project_type

    # 基础环境
    check_homebrew || { _JobsPrint_Red "❌ Homebrew 安装/检测失败"; exit 1; }
    check_fzf
    check_fastlane

    open_fastfile

    _JobsPrint_Green "🎉 完成"
  }

  ########## ✅ 执行入口 ##########
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
