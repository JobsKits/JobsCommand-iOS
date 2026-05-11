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
  # ✅ 日志与语义输出
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

  # ✅ 基础路径配置
  BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
  readonly BASE_DIR
  CONFIG_FILE="$HOME/.cocoapods_mirror_config"

  # ✅ 自述信息
  print_intro() {
    clear
    note_echo "🛠️ 脚本功能简介："
    note_echo "➤ 自动判断当前目录是 iOS 工程还是 Flutter 工程"
    note_echo "➤ 检测 CDN 可用性，缓存并自动切换 CocoaPods 镜像"
    note_echo "➤ 支持 Apple Silicon 使用 Rosetta 执行 pod update"
    note_echo "➤ 更新成功后自动创建桌面 .xcworkspace 快捷方式"
    warn_echo "📌 请确保已安装 CocoaPods 和 fzf"
    echo ""
    read "?👉 按下回车键继续执行，或 Ctrl+C 取消..."
  }

  # ✅ CDN 检测与镜像配置
  check_cdn_available() {
    info_echo "🌐 正在检测 cdn.cocoapods.org 可用性..."
    if curl -I --max-time 3 https://cdn.cocoapods.org/all_pods_versions_c_0_4.txt 2>/dev/null | grep -q "200 OK"; then
      success_echo "CDN 可用"
      return 0
    else
      error_echo "CDN 不可访问，将提示你手动切换镜像"
      return 1
    fi
  }

  switch_cocoapods_source() {
    local sources=("清华源|https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git" "华为源|https://repo.huaweicloud.com/repository/CocoaPods/")
    local selected=$(printf "%s\n" "${sources[@]}" | fzf --prompt="🎯 选择 CocoaPods 镜像源：") || return 1
    local url="${${selected}#*|}"

    info_echo "🧩 正在切换镜像源为：$url"
    pod repo remove trunk >/dev/null 2>&1
    pod repo add trunk "$url"
    echo "$url" > "$CONFIG_FILE"
    success_echo "镜像源设置并缓存成功：$url"
  }

  auto_apply_cached_source() {
    if [[ -f "$CONFIG_FILE" ]]; then
      local url=$(cat "$CONFIG_FILE")
      info_echo "📄 读取镜像缓存：$url"
      if ! pod repo list | grep -q "$url"; then
        info_echo "🔁 当前未配置该镜像，正在切换..."
        pod repo remove trunk >/dev/null 2>&1
        pod repo add trunk "$url"
        success_echo "✅ 镜像源应用成功"
      else
        success_echo "✅ 镜像源已配置，无需切换"
      fi
    else
      check_cdn_available || switch_cocoapods_source
    fi
  }

  # ✅ Pod 更新流程
  update_pod_in_dir() {
    local dir="$1"
    info_echo "📁 正在进入目录：$dir"
    cd "$dir" || {
      error_echo "无法进入目录：$dir"
      exit 1
    }

    auto_apply_cached_source

    local arch="$(uname -m)"
    info_echo "🧠 当前芯片架构：$arch"

    if [[ "$arch" == "arm64" ]]; then
      info_echo "🍎 使用 Rosetta 执行 pod update"
      arch -x86_64 pod update
    else
      info_echo "💻 执行 pod repo update..."
      ask_run "更新 CocoaPods 本地仓库？" && pod repo update
      sleep 1
      ask_run "执行 pod update？" && pod update
    fi

    success_echo "🎉 Pod 更新完成"

    # 创建桌面快捷方式（.xcworkspace）
    local workspace_file
    workspace_file="$(find . -maxdepth 1 -name '*.xcworkspace' | head -n 1)"
    if [[ -n "$workspace_file" ]]; then
      local link="$HOME/Desktop/$(basename "$workspace_file")"
      if [[ -e "$link" || -L "$link" ]]; then
        info_echo "📎 桌面已存在同名链接，跳过创建"
      else
        ln -s "$PWD/$workspace_file" "$link"
        success_echo "📎 已创建桌面快捷方式：$link"
      fi
    else
      warn_echo "⚠️ 未检测到 .xcworkspace 文件"
    fi
  }

  # ✅ 项目类型判断与 Pod 更新
  detect_and_update_project_type() {
    # 判断当前工程类型并执行更新
    if [[ -f "$BASE_DIR/Podfile" ]]; then
      info_echo "📱 检测到 iOS 工程，执行更新..."
      update_pod_in_dir "$BASE_DIR"
    elif [[ -f "$BASE_DIR/pubspec.yaml" && -f "$BASE_DIR/ios/Podfile" ]]; then
      info_echo "🧩 检测到 Flutter 工程，进入 ios 执行 pod update..."
      update_pod_in_dir "$BASE_DIR/ios"
    else
      error_echo "✖ 未找到 Podfile，无法继续执行"
      exit 1
    fi
  }

  # ✅ 主函数入口
  main() {
      print_intro                         # ✅ 自述信息
      detect_and_update_project_type      # ✅ 判断当前工程类型并执行更新
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
