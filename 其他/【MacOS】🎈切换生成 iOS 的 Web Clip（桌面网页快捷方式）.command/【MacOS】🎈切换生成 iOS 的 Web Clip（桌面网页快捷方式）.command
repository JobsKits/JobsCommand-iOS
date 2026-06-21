#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command
# - 核心用途：执行“🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
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
show_readme_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）.command'
  print -r -- '核心用途：执行“🎈切换生成 iOS 的 Web Clip（桌面网页快捷方式）”对应的移动端项目自动化任务。'
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
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
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ================================================================
  # 🧩 iOS WebClip .mobileconfig 自动生成脚本（macOS 原生版）
  # ---------------------------------------------------------------
  # 功能：
  # 1. 生成 iOS 桌面快捷方式（WebClip）配置文件。
  # 2. 支持拖入图片、自动缩放并转 base64。
  # 3. 输出文件 webclip.mobileconfig 到桌面。
  # ---------------------------------------------------------------
  # 作者：JobsHi（macOS 原生脚本封装示例）
  # ================================================================

  set -u  # 禁止未定义变量；不启用 -e 以便自定义错误处理
  # ============================== 自述 ==============================
  show_intro() {
  cat <<'EOF'
  🌈 ===============================================
                iOS WebClip 自动生成工具
  ===============================================
  📘 功能说明：
    • 自动生成 iPhone/iPad 桌面快捷方式配置文件（.mobileconfig）
    • 使用系统自带工具，无需 Python、Pillow 或 Xcode。
    • 图标自动缩放为 64×64 并内嵌为 Base64。
  -----------------------------------------------
  ⚙️ 使用步骤：
    1. 输入网页地址（URL）
    2. 输入桌面显示名称（Label）
    3. 拖入图标文件（PNG/JPG）
    4. 自动输出：~/Desktop/webclip.mobileconfig
  ===============================================
EOF
  read "?👉 按回车键继续 ..."
  }
  # ============================== 工具检测 ==============================
  check_dependencies() {
      for cmd in sips base64 uuidgen; do
          if ! command -v $cmd >/dev/null 2>&1; then
              echo "❌ 缺少依赖：$cmd"
              read -n1 -s -r -p "按任意键退出…"
              exit 1
          fi
      done
  }
  # ============================== 图标验证与转换 ==============================
  clean_path() {
      local raw="$1"
      raw="${raw#\'}"; raw="${raw%\'}"
      raw="${raw#\"}"; raw="${raw%\"}"
      printf '%b' "${raw//\\/\\}"
  }
  # 检查当前运行条件是否满足后续流程要求。
  is_image() {
      local p="$1"
      sips -g pixelWidth "$p" >/dev/null 2>&1 && return 0
      if command -v file >/dev/null 2>&1; then
          file -b --mime-type "$p" | grep -qi '^image/' && return 0
      fi
      return 1
  }
  # 封装 prepare_icon 对应的独立处理逻辑。
  prepare_icon() {
      local icon_path="$1"
      local tmp_icon="/tmp/webclip_icon_64.png"
      sips -z 64 64 "$icon_path" --out "$tmp_icon" >/dev/null 2>&1
      base64 -i "$tmp_icon"
  }
  # ============================== 核心生成逻辑 ==============================
  generate_mobileconfig() {
      local url="$1"
      local label="$2"
      local icon_base64="$3"
      local output="$HOME/Desktop/webclip.mobileconfig"

      local uuid1=$(uuidgen | tr '[:lower:]' '[:upper:]')
      local uuid2=$(uuidgen | tr '[:lower:]' '[:upper:]')

      # 写入配置文件
      cat > "$output" <<EOF
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>PayloadContent</key>
    <array>
      <dict>
        <key>FullScreen</key>
        <true/>
        <key>IsRemovable</key>
        <true/>
        <key>Label</key>
        <string>$label</string>
        <key>PayloadType</key>
        <string>com.apple.webClip.managed</string>
        <key>PayloadUUID</key>
        <string>$uuid1</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
        <key>Precomposed</key>
        <true/>
        <key>URL</key>
        <string>$url</string>
EOF

      if [[ -n "$icon_base64" ]]; then
          cat >> "$output" <<EOF
        <key>Icon</key>
        <data>
  $icon_base64
        </data>
EOF
      fi

      cat >> "$output" <<EOF
      </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>Web Clip Profile</string>
    <key>PayloadIdentifier</key>
    <string>com.jobs.webclip</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>$uuid2</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
  </dict>
  </plist>
EOF

      echo "✅ 已生成：$output"
      open -R "$output"  # 打开 Finder 定位结果
  }
  # ============================== 主函数 ==============================
  main() {
      show_intro
      check_dependencies

      echo
      read "?🌐 请输入网页地址 (例如 https://yourwebsite.com)： " url
      [[ -z "$url" ]] && echo "❌ URL 不能为空" && exit 1

      read "?🏷️ 请输入桌面显示名称： " label
      [[ -z "$label" ]] && echo "❌ 名称不能为空" && exit 1

      echo
      local icon_path=""
      while true; do
          echo "🖼️  请从 Finder 拖入图标文件（PNG/JPG），然后按回车："
          read -r USER_INPUT
          USER_INPUT="${USER_INPUT:-}"
          CLEANED="$(clean_path "$USER_INPUT")"

          if [[ -z "$CLEANED" ]]; then
              echo "⚠️  未检测到输入，请重试。"
              continue
          fi
          if [[ ! -f "$CLEANED" ]]; then
              echo "⚠️  文件不存在：$CLEANED"
              continue
          fi
          if ! is_image "$CLEANED"; then
              echo "⚠️  不是有效图片文件，请重新拖入。"
              continue
          fi
          icon_path="$CLEANED"
          break
      done

      echo "🪄  正在处理图标并生成配置文件..."
      icon_base64="$(prepare_icon "$icon_path")"
      generate_mobileconfig "$url" "$label" "$icon_base64"

      echo
      read -n1 -s -r -p "按任意键关闭窗口…"
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
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
