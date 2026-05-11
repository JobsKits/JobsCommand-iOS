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
  # ✅ 日志与彩色输出
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

  # ✅ 全局初始化配置
  init_env() {
    export CURL_HTTP_VERSION=1.1
    info_echo "📡 强制设置 CURL_HTTP_VERSION=1.1，避免 HTTP2 CDN 拉取错误"

    BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
    cd "$BASE_DIR"
    info_echo "📌 当前起点路径: $BASE_DIR"

    CONFIG_FILE="$HOME/.cocoapods_mirror_config"
  }

  # ✅ CocoaPods CDN 可用性检查
  check_cdn_available() {
    info_echo "🌐 检查 cdn.cocoapods.org 是否可访问..."
    if curl -I --max-time 3 https://cdn.cocoapods.org/all_pods_versions_c_0_4.txt 2>/dev/null | grep -q "200 OK"; then
      success_echo "CDN 可用"
      return 0
    else
      error_echo "🚫 CDN 不可用"
      return 1
    fi
  }

  # ✅ 切换镜像源并保存
  switch_cocoapods_source() {
    local sources=(
      "清华源|https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git"
      "华为源|https://repo.huaweicloud.com/repository/CocoaPods/"
    )
    local selected_source url

    selected_source=$(printf "%s\n" "${sources[@]}" | fzf --prompt="🎯 选择 CocoaPods 镜像源：") || return 1
    url="${${selected_source}#*|}"

    info_echo "🧩 正在切换镜像源为: $url"
    pod repo remove trunk >/dev/null 2>&1 || true
    pod repo add trunk "$url"
    echo "$url" > "$CONFIG_FILE"
    success_echo "📦 已记住镜像源: $url"
  }

  # ✅ 应用缓存或选择镜像源
  auto_apply_cached_source() {
    if [[ -f "$CONFIG_FILE" ]]; then
      local url
      url=$(cat "$CONFIG_FILE")
      info_echo "📄 检测到已缓存镜像源: $url"

      if ! pod repo list | grep -q "$url"; then
        info_echo "🔁 当前未配置该源，自动切换中..."
        pod repo remove trunk >/dev/null 2>&1 || true
        pod repo add trunk "$url"
        success_echo "📦 镜像源已应用: $url"
      else
        success_echo "🧠 镜像源已是缓存设置，无需变更"
      fi
    else
      check_cdn_available || switch_cocoapods_source
    fi
  }

  # ✅ 执行 pod install 操作
  install_pod() {
    local dir="$1"
    info_echo "📁 进入目录: $dir"
    cd "$dir" || { error_echo "❌ 无法进入目录: $dir"; exit 1; }

    local arch="$(uname -m)"
    local POD_CMD="pod install --repo-update --verbose"
    info_echo "🧠 当前架构: $arch"

    if [[ "$arch" == "arm64" ]]; then
      local pod_binary="$(which pod)"
      [[ -z "$pod_binary" ]] && error_echo "❌ 未找到 pod 命令" && exit 1

      local arch_info="$(lipo -info "$pod_binary")"
      info_echo "🧩 pod 架构信息: $arch_info"

      if echo "$arch_info" | grep -q "x86_64"; then
        info_echo "🍎 使用 Rosetta 模式执行"
        POD_CMD="arch -x86_64 $POD_CMD"
      else
        info_echo "💻 直接执行 pod install"
      fi
    fi

    info_echo "⚙️ 执行命令: $POD_CMD"
    eval "$POD_CMD"
    success_echo "🎉 Pod 安装完成"

    create_desktop_shortcut_if_needed
  }

  # ✅ 创建桌面快捷方式（如有 .xcworkspace）
  create_desktop_shortcut_if_needed() {
    local workspace_file
    workspace_file="$(find . -maxdepth 1 -name '*.xcworkspace' | head -n 1)"

    if [[ -n "$workspace_file" ]]; then
      local name="$(basename "$workspace_file")"
      local link="$HOME/Desktop/$name"

      if [[ -e "$link" || -L "$link" ]]; then
        info_echo "🔗 桌面已存在快捷方式，跳过创建"
      else
        ln -s "$PWD/$name" "$link"
        success_echo "📎 已在桌面创建快捷方式: $name"
      fi
    else
      error_echo "❌ 未检测到生成的 .xcworkspace 文件"
    fi
  }

  # ✅ 检测项目类型并执行 pod 安装
  detect_project_type_and_install() {
    if [[ -f "$BASE_DIR/Podfile" ]]; then
      info_echo "📱 检测到 iOS 工程"
      auto_apply_cached_source
      install_pod "$BASE_DIR"

    elif [[ -f "$BASE_DIR/pubspec.yaml" && -f "$BASE_DIR/ios/Podfile" ]]; then
      info_echo "🧩 检测到 Flutter 工程，进入 ios 目录执行 pod install"
      auto_apply_cached_source
      install_pod "$BASE_DIR/ios"

    else
      error_echo "❌ 未找到 Podfile，无法继续"
      exit 1
    fi
  }

  # ✅ 主函数入口
  main() {
    init_env                            # 🌐 初始化环境变量和目录路径
    detect_project_type_and_install     # 检测项目类型并执行 pod 安装
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
