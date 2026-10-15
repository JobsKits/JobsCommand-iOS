#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📱双击初始化iOS模拟器.command
# - 核心用途：交互选择 iPhone 设备型号和 iOS Runtime，创建并启动一个新的 iOS 模拟器。
# - 影响范围：会读取 Xcode 模拟器环境；默认只温和处理疑似假后台 Simulator，不会无差别关闭已启动模拟器。
# - 运行提示：运行后会先打印内置自述；确认后继续，强制关闭模拟器必须输入 YES。

# ✅ 日志输出函数
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
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
  highlight_echo "══════════════════════════════ 脚本自述 ══════════════════════════════" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：使用 fzf 选择 iPhone 设备与 iOS 系统版本，创建并启动新模拟器。" | jobs_intro_style body
  warn_echo "影响范围：会探测 Xcode 构建状态和已启动模拟器；默认不关闭正在使用的模拟器。" | jobs_intro_style body
  warn_echo "清理策略：仅在无 Booted 设备但 Simulator 残留时，温和退出 Simulator.app。" | jobs_intro_style body
  warn_echo "强制清场：只有输入 YES 才会执行 shutdown all / quit / pkill。" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  gray_echo "取消方式：按 Ctrl+C 终止，不会继续执行后续业务。" | jobs_intro_style body
  highlight_echo "═════════════════════════════════════════════════════════════════════" | jobs_intro_style title
  echo "" | jobs_intro_style body
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
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
  local arch="$(get_cpu_arch)"                   # 获取当前架构（arm64 或 x86_64）
  local shell_path="${SHELL##*/}"                # 获取当前 shell 名称（如 zsh、bash）
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""
  local user_input=""

  if ! jobs_brew_find >/dev/null; then
    warn_echo "🧩 未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || {
        error_echo "❌ Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || {
        error_echo "❌ Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
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
