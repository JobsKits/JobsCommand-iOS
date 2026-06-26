#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📱双击初始化iOS模拟器.command
# - 核心用途：交互选择 iPhone 设备型号和 iOS Runtime，创建并启动一个新的 iOS 模拟器。
# - 影响范围：会读取 Xcode 模拟器环境；默认只温和处理疑似假后台 Simulator，不会无差别关闭已启动模拟器。
# - 运行提示：运行后会先打印内置自述；确认后继续，强制关闭模拟器必须输入 YES。

# ✅ 日志输出函数
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
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

# ✅ 打印脚本内置自述，并等待用户确认后继续。
show_script_intro_and_wait() {
  : > "$LOG_FILE"
  clear
  highlight_echo "══════════════════════════════ 脚本自述 ══════════════════════════════"
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：使用 fzf 选择 iPhone 设备与 iOS 系统版本，创建并启动新模拟器。"
  warn_echo "影响范围：会探测 Xcode 构建状态和已启动模拟器；默认不关闭正在使用的模拟器。"
  warn_echo "清理策略：仅在无 Booted 设备但 Simulator 残留时，温和退出 Simulator.app。"
  warn_echo "强制清场：只有输入 YES 才会执行 shutdown all / quit / pkill。"
  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "取消方式：按 Ctrl+C 终止，不会继续执行后续业务。"
  highlight_echo "═════════════════════════════════════════════════════════════════════"
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}

# ✅ 初始化 Shell 运行选项。
configure_shell_runtime() {
  setopt NO_NOMATCH
}

# ✅ 判断当前是否存在 Xcode / xcodebuild 构建相关进程。
is_xcode_build_active() {
  pgrep -f "xcodebuild" >/dev/null 2>&1 && return 0
  pgrep -f "XCBBuildService" >/dev/null 2>&1 && return 0
  return 1
}

# ✅ 输出当前已启动的模拟器设备列表。
get_booted_simulators() {
  xcrun simctl list devices booted 2>/dev/null | grep -E "\\(Booted\\)" || true
}

# ✅ 判断 Simulator.app 是否仍有进程残留。
is_simulator_app_running() {
  pgrep -x "Simulator" >/dev/null 2>&1
}

# ✅ 危险操作必须输入 YES 才允许继续。
confirm_yes() {
  echo ""
  warn_echo "$1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

# ✅ 强制关闭所有模拟器和 Simulator 残留进程。
force_shutdown_simulators() {
  warn_echo "🛑 正在强制关闭所有 iOS 模拟器..."
  xcrun simctl shutdown all >/dev/null 2>&1
  osascript -e 'quit app "Simulator"' >/dev/null 2>&1
  sleep 1
  if pgrep -x "Simulator" >/dev/null 2>&1; then
    pkill -x "Simulator" >/dev/null 2>&1
  fi
  success_echo "✅ 已执行强制模拟器清场"
}

# ✅ 按风险分级清理疑似假后台 Simulator，避免影响 Xcode 编译。
cleanup_simulator_background_safely() {
  local booted_simulators=""
  booted_simulators="$(get_booted_simulators)"

  if is_xcode_build_active; then
    warn_echo "⚠️ 检测到 Xcode / xcodebuild 构建相关进程，默认跳过模拟器清理，避免中断编译。"
    if confirm_yes "如果你确认要强制关闭所有模拟器，请输入 YES。"; then
      force_shutdown_simulators
    else
      warn_echo "⏭️ 已跳过模拟器清理"
    fi
    return 0
  fi

  if [[ -n "$booted_simulators" ]]; then
    warn_echo "⚠️ 检测到当前已有 Booted 模拟器，默认认为它正在被使用，不执行 shutdown all。"
    gray_echo "$booted_simulators"
    if confirm_yes "如果你确认要强制关闭所有 Booted 模拟器，请输入 YES。"; then
      force_shutdown_simulators
    else
      warn_echo "⏭️ 已保留当前已启动模拟器"
    fi
    return 0
  fi

  if is_simulator_app_running; then
    warn_echo "🧹 检测到 Simulator.app 进程残留，但没有 Booted 模拟器；按疑似假后台温和退出。"
    osascript -e 'quit app "Simulator"' >/dev/null 2>&1
    sleep 1
    success_echo "✅ 已温和退出疑似假后台 Simulator.app"
  else
    success_echo "✅ 未发现需要清理的模拟器后台残留"
  fi
}

# ✅ 单行写文件（避免重复写入）
inject_shellenv_block() {
    local id="$1"           # 参数1：环境变量块 ID，如 "homebrew_env"
    local shellenv="$2"     # 参数2：实际要写入的 shellenv 内容，如 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    local header="# >>> ${id} 环境变量 >>>"  # 自动生成注释头

    # 参数校验
    if [[ -z "$id" || -z "$shellenv" ]]; then
    error_echo "❌ 缺少参数：inject_shellenv_block <id> <shellenv>"
    return 1
    fi

    # 若用户未选择该 ID，则跳过写入
    if [[ ! " ${selected_envs[*]} " =~ " $id " ]]; then
    warn_echo "⏭️ 用户未选择写入环境：$id，跳过"
    return 0
    fi

    # 避免重复写入
    if grep -Fq "$header" "$PROFILE_FILE"; then
      info_echo "📌 已存在 header：$header"
    elif grep -Fq "$shellenv" "$PROFILE_FILE"; then
      info_echo "📌 已存在 shellenv：$shellenv"
    else
      echo "" >> "$PROFILE_FILE"
      echo "$header" >> "$PROFILE_FILE"
      echo "$shellenv" >> "$PROFILE_FILE"
      success_echo "✅ 已写入：$header"
    fi

    # 当前 shell 生效
    eval "$shellenv"
    success_echo "🟢 shellenv 已在当前终端生效"
}

# ✅ 判断芯片架构（ARM64 / x86_64）
get_cpu_arch() {
  [[ $(uname -m) == "arm64" ]] && echo "arm64" || echo "x86_64"
}

# ✅ 自检安装 🍺 Homebrew（自动架构判断）
install_homebrew() {
  local arch="$(get_cpu_arch)"                   # 获取当前架构（arm64 或 x86_64）
  local shell_path="${SHELL##*/}"                # 获取当前 shell 名称（如 zsh、bash）
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""
  local user_input=""

  if ! command -v brew &>/dev/null; then
    warn_echo "🧩 未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "❌ Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "❌ Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="/usr/local/bin/brew"
    fi

    success_echo "✅ Homebrew 安装成功"

    # ==== 注入 shellenv 到对应配置文件（自动生效） ====
    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""

    case "$shell_path" in
      zsh)   profile_file="$HOME/.zprofile" ;;
      bash)  profile_file="$HOME/.bash_profile" ;;
      *)     profile_file="$HOME/.profile" ;;
    esac

    PROFILE_FILE="$profile_file"
    selected_envs=("homebrew_env")
    inject_shellenv_block "homebrew_env" "$shellenv_cmd"

  else
    echo ""
    note_echo "📦 检测到 Homebrew 已安装"
    gray_echo "直接回车：跳过更新"
    gray_echo "输入任意字符后回车：执行更新升级"
    read "?👉 是否更新 Homebrew：" user_input

    if [[ -n "$user_input" ]]; then
      info_echo "🔄 开始更新 Homebrew..."
      brew update && brew upgrade && brew cleanup && brew doctor && brew -v
      success_echo "✅ Homebrew 已更新"
    else
      warn_echo "⏭️ 已跳过 Homebrew 更新"
    fi
  fi
}

# ✅ 自检安装 Homebrew.fzf
install_fzf() {
  local user_input=""

  if ! command -v fzf &>/dev/null; then
    note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
    brew install fzf || { error_echo "❌ fzf 安装失败"; exit 1; }
    success_echo "✅ fzf 安装成功"
  else
    echo ""
    note_echo "📦 检测到 fzf 已安装"
    gray_echo "直接回车：跳过更新"
    gray_echo "输入任意字符后回车：执行更新升级"
    read "?👉 是否更新 fzf：" user_input

    if [[ -n "$user_input" ]]; then
      info_echo "🔄 开始升级 fzf..."
      brew upgrade fzf && brew cleanup
      success_echo "✅ fzf 已是最新版"
    else
      warn_echo "⏭️ 已跳过 fzf 更新"
    fi
  fi
}

# ✅ 选择要创建的 iPhone 设备型号。
select_device_type() {
  info_echo "📦 获取可用设备类型..."
  device_options=("${(@f)$(xcrun simctl list devicetypes | grep '^iPhone' | sed -E 's/^(.+) \((.+)\)$/📱 \1|\2/')}")
  [[ ${#device_options[@]} -eq 0 ]] && error_echo "❌ 未找到设备类型" && exit 1

  selected_device_display=$(printf "%s\n" "${device_options[@]}" | cut -d'|' -f1 | fzf --prompt="👉 选择设备型号 > " --height=40% --reverse)
  [[ -z "$selected_device_display" ]] && warn_echo "⚠️ 未选择设备，正在退出..." && exit 0

  for entry in "${device_options[@]}"; do
    [[ "${entry%%|*}" == "$selected_device_display" ]] && selected_device_id="${entry##*|}" && break
  done

  success_echo "✔ 你选择的设备是：$selected_device_display"
  success_echo "🔗 设备 ID：$selected_device_id"
}

# ✅ 选择要创建的 iOS Runtime 系统版本。
select_runtime() {
  info_echo "🧬 获取可用系统版本..."

  runtime_options=()
  typeset -A seen_runtime_displays

  local runtime_display=""
  local runtime_id=""
  local entry=""
  local duplicate_runtime_count=0

  # xcrun simctl list runtimes 有时会返回多个 Runtime 记录，但展示名同为 “iOS x.y”。
  # 原脚本只把展示名交给 fzf，所以会出现同一个系统版本显示两次。
  # 这里按展示名去重，保留第一条可用 Runtime ID。
  while IFS='|' read -r runtime_display runtime_id; do
    [[ -z "$runtime_display" || -z "$runtime_id" ]] && continue

    if [[ -n "${seen_runtime_displays[$runtime_display]}" ]]; then
      duplicate_runtime_count=$((duplicate_runtime_count + 1))
      continue
    fi

    seen_runtime_displays[$runtime_display]=1
    runtime_options+=("${runtime_display}|${runtime_id}")
  done < <(
    xcrun simctl list runtimes |
      grep "iOS" |
      grep -v "unavailable" |
      sed -En 's/^.*(iOS [0-9.]+) \([^)]+\) - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[^[:space:]]+).*$/🧬 \1|\2/p'
  )

  [[ ${#runtime_options[@]} -eq 0 ]] && error_echo "❌ 未找到 Runtime" && exit 1

  if [[ $duplicate_runtime_count -gt 0 ]]; then
    gray_echo "已自动去重 ${duplicate_runtime_count} 条重复系统版本"
  fi

  if [[ ${#runtime_options[@]} -eq 1 ]]; then
    selected_runtime_display="${runtime_options[1]%%|*}"
    selected_runtime_id="${runtime_options[1]##*|}"
    success_echo "✔ 仅检测到一个可用系统版本，已自动选择：$selected_runtime_display"
    success_echo "🔗 Runtime ID：$selected_runtime_id"
    return 0
  fi

  selected_runtime_display=$(printf "%s\n" "${runtime_options[@]}" | cut -d'|' -f1 | fzf --prompt="👉 选择系统版本 > " --height=40% --reverse)
  [[ -z "$selected_runtime_display" ]] && warn_echo "⚠️ 未选择系统版本，正在退出..." && exit 0

  for entry in "${runtime_options[@]}"; do
    [[ "${entry%%|*}" == "$selected_runtime_display" ]] && selected_runtime_id="${entry##*|}" && break
  done

  success_echo "✔ 你选择的系统版本是：$selected_runtime_display"
  success_echo "🔗 Runtime ID：$selected_runtime_id"
}

# ✅ 创建并启动选择好的 iOS 模拟器。
create_and_boot_simulator() {
  device_name="${selected_device_display#📱 }"
  datetime=$(date "+%Y.%m.%d %H:%M:%S")
  sim_name="${device_name}@${datetime}"
  info_echo "🚀 正在创建模拟器 $sim_name ..."
  sim_create_output=$(xcrun simctl create "$sim_name" "$selected_device_id" "$selected_runtime_id" 2>&1)

  if [[ "$sim_create_output" == *"Unable to create a device for device type"* ]]; then
    error_echo "❌ 创建失败：该组合不受支持"
    note_echo "💡 设备：$device_name"
    note_echo "💡 系统：${selected_runtime_display#🧬 }"
    warm_echo "🔁 请重新选择有效组合..."
    sleep 2
    return 1
  elif [[ -z "$sim_create_output" ]]; then
    error_echo "❌ 模拟器创建失败（未知错误）"
    sleep 1
    return 1
  else
    sim_id="$sim_create_output"
    success_echo "✔ 模拟器创建成功：$sim_name"
    success_echo "🆔 模拟器 ID：$sim_id"
    info_echo "🚀 启动模拟器中..."
    xcrun simctl boot "$sim_id" >/dev/null 2>&1
    open -a Simulator
    success_echo "✅ 模拟器已打开：$sim_name"
    return 0
  fi
}

# ✅ 启动交互式模拟器创建循环
interactive_simulator_creation_loop() {
  while true; do
    echo ""
    note_echo "📌 如果你想复制上面命令，请现在复制完再按回车继续..."
    read "?⏸️ 按回车继续选择设备和系统："

    select_device_type                      # ✅ 选择设备型号
    echo ""
    select_runtime                          # ✅ 选择系统版本
    echo ""

    create_and_boot_simulator && break      # ✅ 创建成功则退出循环，否则重新选择
  done
}

main() {
    show_script_intro_and_wait              # ✅ 打印脚本内置自述并等待用户确认
    configure_shell_runtime                 # ✅ 初始化 Shell 运行选项
    cleanup_simulator_background_safely     # ✅ 分级清理疑似假后台 Simulator
    install_homebrew                        # ✅ 自检安装 🍺 Homebrew（自动架构判断）
    install_fzf                             # ✅ 自检安装 Homebrew.fzf
    interactive_simulator_creation_loop     # ✅ 启动交互式模拟器创建循环
}

main "$@"
