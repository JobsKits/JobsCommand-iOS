#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📱双击初始化iOS模拟器.command
# - 核心用途：先选择完整 iPhone / iPad 型号，再选择 iOS Runtime，创建并启动一个新的 iOS 模拟器。
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

# >>> Jobs iOS simulator core >>>
typeset SCRIPT_DIR=""
typeset SCRIPT_PATH=""
typeset SCRIPT_BASENAME=""
typeset LOG_FILE=""
typeset SIM_MODE="interactive"
typeset SIM_RUN_DIR=""
typeset SIM_ACTIVE_PID=""
typeset SIM_DEVELOPER_DIR=""
typeset SIM_APP=""
typeset SIM_APP_KIND=""
typeset SIM_FZF=""
typeset SIM_SELECTED_ROW=""
typeset SIM_RUNTIME_ID=""
typeset SIM_RUNTIME_NAME=""
typeset SIM_DEVICE_ID=""
typeset SIM_DEVICE_NAME=""
typeset SIM_NAME=""
typeset SIM_UDID=""
typeset SIM_LOG_READY=0
typeset SIM_CANCELLED=0
typeset -a SIM_ROWS

# 仅设置进程内选项、路径及纯文本 / 彩色展示条件。
sim_prepare_context() {
    setopt NO_NOMATCH PIPE_FAIL
    SCRIPT_PATH="${ZSH_ARGZERO:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$$.log"
}
# 同步显示与日志；磁盘日志始终保持纯文本。
sim_log() {
    print -r -- "$1"
    if [[ "$SIM_LOG_READY" == 1 ]]; then
        print -r -- "$1" >> "$LOG_FILE"
    fi
}
# 按 Jobs 标准显示自述，非完整终端自动降级为纯文本。
sim_intro_line() {
    local role="$1" message="$2"
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        if [[ "$role" == title ]]; then
            printf '\033[1;31m%s\033[0m\n' "$message"
        else
            printf '\033[0;34m%s\033[0m\n' "$message"
        fi
    else
        print -r -- "$message"
    fi
}
# 在任何真实动作前解析只读入口，并对交互入口完成终端检查和首次确认。
sim_confirm_entry() {
    case "$#:${1:-}" in
        0:) SIM_MODE=interactive ;;
        1:--help|1:-h) SIM_MODE=help; return 0 ;;
        1:--check) SIM_MODE=check; return 0 ;;
        *) sim_log '✖ 参数无效。使用 --help 查看说明。'; exit 64 ;;
    esac
    if [[ ! -t 0 || ! -t 1 ]]; then
        sim_log '✖ 当前没有可交互终端，请通过 Finder 入口或 Terminal 运行；不会创建模拟器。'
        exit 1
    fi
    local answer=""
    IFS= read -r "?已了解影响，直接回车继续；输入任意字符取消：" answer || exit 130
    if [[ -n "$answer" ]]; then
        sim_log '➤ 已取消，未创建模拟器。'
        exit 0
    fi
}
# 清理本次私有临时文件，不触碰 CoreSimulator 或其它会话。
sim_cleanup() {
    if [[ -n "$SIM_ACTIVE_PID" ]]; then
        kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
        /bin/sleep 0.2
        kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
        wait "$SIM_ACTIVE_PID" 2>/dev/null
        SIM_ACTIVE_PID=""
    fi
    if [[ -n "$SIM_RUN_DIR" && -d "$SIM_RUN_DIR" ]]; then
        /bin/rm -f -- "$SIM_RUN_DIR"/runtimes.json "$SIM_RUN_DIR"/devicetypes.json "$SIM_RUN_DIR"/devices.json "$SIM_RUN_DIR"/command.out
        /bin/rmdir -- "$SIM_RUN_DIR" 2>/dev/null
    fi
}
# 中断只停止当前命令，已创建的设备保留，并显示可追踪的 UDID。
sim_handle_signal() {
    sim_log '⚠ 已停止当前操作。'
    if [[ -n "$SIM_UDID" ]]; then
        sim_log "➤ 新设备已保留：${SIM_NAME}（${SIM_UDID}）。可在 Simulator 中继续启动。"
    fi
    exit 130
}
# zsh 在脚本退出时清理；顶层特殊函数避免函数内部 EXIT trap 提前清理目录。
TRAPEXIT() {
    sim_cleanup
}
# 将终端中断转为有提示的安全停止。
TRAPINT() {
    sim_handle_signal
}
# 关闭终端时保留已创建的设备并停止当前命令。
TRAPHUP() {
    sim_handle_signal
}
# 外部终止遵循相同的保留设备策略。
TRAPTERM() {
    sim_handle_signal
}
# 确认后准备私有临时目录；只读体检仅使用临时快照，不保留日志。
sim_initialize_runtime() {
    local old_umask="$(umask)"
    umask 077
    SIM_RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.XXXXXX")" || exit 1
    if [[ "$SIM_MODE" == interactive ]]; then
        if ! (setopt NO_CLOBBER; : > "$LOG_FILE") 2>/dev/null; then
            sim_log "✖ 无法安全创建日志：${LOG_FILE}"
            /bin/rmdir -- "$SIM_RUN_DIR"
            exit 1
        fi
        SIM_LOG_READY=1
    fi
    umask "$old_umask"
    if [[ "$SIM_MODE" == interactive ]]; then
        sim_log "➤ 创建阶段：只新增模拟器；保留现有设备。日志：${LOG_FILE}"
    else
        sim_log '➤ 操作：只读检查，临时快照退出时清理，不创建日志。'
    fi
}
# 以有限等待运行指定命令，超时停止本次进程，保留输出供错误定位。
sim_run_to_file() {
    local output="$1" limit="$2"
    shift 2
    local ticks=0 result=0
    "$@" > "$output" 2>&1 &
    SIM_ACTIVE_PID=$!
    while kill -0 "$SIM_ACTIVE_PID" 2>/dev/null; do
        if (( ticks >= limit * 10 )); then
            kill -TERM "$SIM_ACTIVE_PID" 2>/dev/null
            /bin/sleep 0.2
            kill -KILL "$SIM_ACTIVE_PID" 2>/dev/null
            wait "$SIM_ACTIVE_PID" 2>/dev/null
            SIM_ACTIVE_PID=""
            sim_log "✖ 命令等待超过 ${limit} 秒：$*"
            return 124
        fi
        /bin/sleep 0.1
        (( ticks += 1 ))
    done
    wait "$SIM_ACTIVE_PID" || result=$?
    SIM_ACTIVE_PID=""
    return "$result"
}
# 使用系统 JXA 解析 simctl JSON，避免依赖 Homebrew、Python 或 jq。
sim_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(args) {
    function json(path) {
        var data = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
        if (!data) throw Error('无法读取模拟器快照：' + path);
        return JSON.parse(ObjC.unwrap(data));
    }
    function text(value) {
        if (typeof value !== 'string' || !value || /[\x00-\x1f\x7f]/.test(value)) throw Error('模拟器字段无效或包含控制字符');
        return value;
    }
    function id(value, prefix) {
        if (!text(value).startsWith(prefix) || !/^[A-Za-z0-9._-]+$/.test(value)) throw Error('模拟器标识格式无效');
        return value;
    }
    function version(value) {
        if (typeof value !== 'string' || !/^\d+(?:\.\d+){0,2}$/.test(value)) throw Error('系统版本格式无效');
        var parts = value.split('.').map(Number);
        while (parts.length < 3) parts.push(0);
        return parts[0] * 65536 + parts[1] * 256 + parts[2];
    }
    function runtimeList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.runtimes)) throw Error('Runtime JSON 缺少 runtimes 数组');
        return value.runtimes;
    }
    function deviceList(path) {
        var value = json(path);
        if (!value || !Array.isArray(value.devicetypes)) throw Error('设备 JSON 缺少 devicetypes 数组');
        return value.devicetypes;
    }
    function availableRuntimes(path, arch) {
        var seen = Object.create(null), seenIDs = Object.create(null), rows = [];
        runtimeList(path).forEach(function (entry) {
            if (entry.isAvailable !== true || !/^com\.apple\.CoreSimulator\.SimRuntime\.iOS-/.test(entry.identifier || '')) return;
            if (Array.isArray(entry.supportedArchitectures) && entry.supportedArchitectures.indexOf(arch) < 0) return;
            var name = text(entry.name), identifier = id(entry.identifier, 'com.apple.CoreSimulator.SimRuntime.iOS-');
            var value = version(entry.version);
            if (seen[name] || seenIDs[identifier]) return;
            seen[name] = true;
            seenIDs[identifier] = true;
            rows.push({name:name, id:identifier, value:value, entry:entry});
        });
        rows.sort(function (a,b) { return b.value - a.value || a.name.localeCompare(b.name); });
        return rows;
    }
    function namedDevices(path) {
        var seen = Object.create(null), rows = [];
        deviceList(path).forEach(function (device) {
            if (!/^iPhone |^iPad /.test(device.name || '')) return;
            var identifier = id(device.identifier, 'com.apple.CoreSimulator.SimDeviceType.'), name = text(device.name);
            if (seen[identifier]) return;
            seen[identifier] = true;
            rows.push({name:name, id:identifier, entry:device});
        });
        return rows;
    }
    function runtimeBound(device, prefix) {
        var value = device[prefix + 'RuntimeVersion'];
        if (typeof value === 'number' && isFinite(value) && value >= 0 && Math.floor(value) === value) return value;
        value = device[prefix + 'RuntimeVersionString'];
        return typeof value === 'string' && /^\d+(?:\.\d+){0,2}$/.test(value) ? version(value) : null;
    }
    // 有效标识白名单；字段缺失或为空数组时没有结论，返回 null 交给版本范围判断。
    function supportIdentifiers(runtime) {
        var supported = runtime.entry.supportedDeviceTypes;
        if (!Array.isArray(supported) || supported.length === 0) return null;
        return supported.map(function (entry) {
            var identifier = typeof entry === 'string' ? entry : entry && entry.identifier;
            return typeof identifier === 'string' && /^com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9._-]+$/.test(identifier) ? identifier : null;
        });
    }
    // 只排除有明确依据的组合；缺失或不完整的兼容元数据保留为未知。
    function compatibility(device, runtime) {
        var identifiers = supportIdentifiers(runtime);
        if (identifiers) {
            if (identifiers.indexOf(device.id) >= 0) return 2;
            if (identifiers.every(function (identifier) { return identifier !== null; })) return 0;
        }
        var minimum = runtimeBound(device.entry, 'min'), maximum = runtimeBound(device.entry, 'max');
        if (minimum !== null && maximum !== null && minimum > maximum) return 1;
        if (minimum !== null && runtime.value < minimum) return 0;
        if (maximum !== null && runtime.value > maximum) return 0;
        return 1;
    }
    if (args[0] === 'health') return 'jxa-ready';
    if (args[0] === 'app') {
        var appPath = text(args[1]), bundle = $.NSBundle.bundleWithPath(appPath);
        var bundleID = ObjC.unwrap(bundle.bundleIdentifier);
        if (bundleID !== 'com.apple.iphonesimulator' && bundleID !== 'com.apple.dt.Devices') throw Error('模拟器应用 Bundle ID 无效');
        var executable = ObjC.unwrap(bundle.executablePath);
        if (!executable || !$.NSFileManager.defaultManager.isExecutableFileAtPath(executable)) throw Error('模拟器应用可执行文件缺失');
        return bundleID;
    }
    if (args[0] === 'runtimes') {
        return availableRuntimes(args[1], args[2]).map(function (row) { return row.name + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'devicetypes') {
        return namedDevices(args[1]).map(function (row) { return row.name + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'preferred-devicetypes') {
        var devices = namedDevices(args[1]), runtimes = availableRuntimes(args[2], args[3]);
        devices.forEach(function (device, index) {
            device.order = index;
            device.rank = runtimes.reduce(function (rank, runtime) { return Math.max(rank, compatibility(device, runtime)); }, 0);
        });
        devices.sort(function (a,b) { return b.rank - a.rank || a.order - b.order; });
        // 无可搭配系统的型号永远走不到命名与创建，标注不会污染设备名。
        return devices.map(function (row) { return (row.rank === 0 ? row.name + '（本机无可搭配系统）' : row.name) + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'compatible-runtimes') {
        var selectedID = id(args[4], 'com.apple.CoreSimulator.SimDeviceType.');
        var devices = namedDevices(args[3]).filter(function (device) { return device.id === selectedID; });
        if (devices.length !== 1) throw Error('所选型号不属于当前设备清单');
        var runtimes = availableRuntimes(args[1], args[2]);
        runtimes.forEach(function (runtime) { runtime.rank = compatibility(devices[0], runtime); });
        runtimes = runtimes.filter(function (runtime) { return runtime.rank > 0; });
        runtimes.sort(function (a,b) { return b.rank - a.rank || b.value - a.value || a.name.localeCompare(b.name); });
        // 系统名只用于展示与日志，标注不会进入 simctl create 的参数。
        return runtimes.map(function (row) { return (row.rank === 2 ? row.name : row.name + '（未确认支持）') + '\t' + row.id; }).join('\n');
    }
    if (args[0] === 'catalog-summary') {
        var summaryDevices = namedDevices(args[1]), summaryRuntimes = availableRuntimes(args[2], args[3]);
        summaryDevices.forEach(function (device) {
            device.rank = summaryRuntimes.reduce(function (rank, runtime) { return Math.max(rank, compatibility(device, runtime)); }, 0);
        });
        var matched = summaryDevices.filter(function (device) { return device.rank > 0; }).length;
        var lines = ['models\t' + summaryDevices.length + '\t' + matched + '\t' + (summaryDevices.length - matched)];
        summaryRuntimes.forEach(function (runtime) {
            var identifiers = supportIdentifiers(runtime), count = -1;
            if (identifiers && identifiers.every(function (identifier) { return identifier !== null; })) {
                count = summaryDevices.filter(function (device) { return identifiers.indexOf(device.id) >= 0; }).length;
            }
            lines.push('runtime\t' + runtime.name + '\t' + count);
        });
        return lines.join('\n');
    }
    if (args[0] === 'unique-name') {
        var payload = json(args[1]), names = Object.create(null), base = text(args[2]);
        if (!payload || !payload.devices || Array.isArray(payload.devices) || typeof payload.devices !== 'object') throw Error('已有设备 JSON 缺少 devices 对象');
        Object.keys(payload.devices).forEach(function (runtime) {
            if (!Array.isArray(payload.devices[runtime])) throw Error('已有设备 JSON 格式无效');
            payload.devices[runtime].forEach(function (device) { names[text(device.name)] = true; });
        });
        var name = base, suffix = 2;
        while (names[name]) name = base + ' (' + suffix++ + ')';
        return name;
    }
    throw Error('未知数据操作');
}
JXA
}
# 体检当前 Xcode 工具链及系统解析器，不变更 xcode-select 或安装任何依赖。
sim_check_environment() {
    local output="$SIM_RUN_DIR/command.out" simctl_path="" jxa_health="" candidate="" app_kind=""
    if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
        sim_log '✖ 此脚本仅适用于 macOS。'
        return 1
    fi
    if ! sim_run_to_file "$output" 20 /usr/bin/xcrun --find simctl; then
        sim_log '✖ xcrun 无法定位 simctl。请安装完整 Xcode，完成首次启动与组件安装。'
        sim_log "$(<"$output")"
        return 1
    fi
    simctl_path="$(<"$output")"
    if [[ ! -x "$simctl_path" || "$simctl_path" != */usr/bin/simctl ]]; then
        sim_log "✖ simctl 路径不可执行：${simctl_path}"
        return 1
    fi
    SIM_DEVELOPER_DIR="${simctl_path%/usr/bin/simctl}"
    if ! jxa_health="$(sim_data health 2>&1)" || [[ "$jxa_health" != jxa-ready ]]; then
        sim_log "✖ 系统 JavaScript for Automation 不可用：${jxa_health}"
        return 1
    fi
    SIM_APP=""
    SIM_APP_KIND=""
    for candidate in "$SIM_DEVELOPER_DIR/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/Simulator.app" "${SIM_DEVELOPER_DIR:h}/Applications/DeviceHub.app"; do
        [[ -d "$candidate" ]] || continue
        if app_kind="$(sim_data app "$candidate" 2>&1)"; then
            SIM_APP="$candidate"
            SIM_APP_KIND="$app_kind"
            break
        fi
    done
    if [[ -z "$SIM_APP" ]]; then
        sim_log "✖ 当前 Xcode 缺少健康的 Simulator / Device Hub：${SIM_DEVELOPER_DIR}"
        return 1
    fi
    sim_log "✔ 当前 Xcode 工具链：${SIM_DEVELOPER_DIR}"
}
# 单独复检选择器，独立入口安装依赖后即可刷新而不重复体检 Xcode。
sim_check_selector() {
    local output="$SIM_RUN_DIR/command.out"
    SIM_FZF="$(command -v fzf 2>/dev/null)"
    if [[ -n "$SIM_FZF" ]]; then
        if ! sim_run_to_file "$output" 5 "$SIM_FZF" --version; then
            SIM_FZF=""
        fi
    fi
    if [[ -n "$SIM_FZF" ]]; then
        sim_log '➤ 选择方式：本机健康 fzf（系统版本按 ← 返回型号，Esc 取消）。'
    else
        sim_log '✖ fzf 缺失或不可用，已停止交互选择；请先运行独立入口的依赖自检，或修复 fzf 后重试。'
        return 1
    fi
}
# 获取结构化清单，任一命令失败都停止，不把错误文本当作设备数据。
sim_load_catalog() {
    local kind="" file=""
    for kind in runtimes devicetypes devices; do
        file="$SIM_RUN_DIR/${kind}.json"
        if ! sim_run_to_file "$file" 30 /usr/bin/xcrun simctl list "$kind" --json; then
            sim_log "✖ 读取模拟器清单失败：xcrun simctl list ${kind} --json"
            sim_log "$(<"$file")"
            return 1
        fi
    done
}
# 选择真实清单行；子层用左键返回，取消与选择器失败分别传播。
sim_choose_row() {
    local title="$1" content="$2" allow_back="${3:-0}" result=0 output="" key=""
    local -a picker_args
    SIM_SELECTED_ROW=""
    SIM_ROWS=("${(@f)content}")
    if [[ -z "$content" || ${#SIM_ROWS} == 0 ]]; then
        return 2
    fi
    sim_log "➤ ${title}"
    [[ -n "$SIM_FZF" ]] || sim_check_selector || return $?
    picker_args=(--delimiter=$'\t' --with-nth=1 --height=60% --reverse --prompt="${title} > " --header='回车确认；Esc / Ctrl+C 取消')
    if (( allow_back )); then
        picker_args+=(--expect=left --header='← 返回型号选择；回车确认；Esc / Ctrl+C 取消')
    fi
    output="$(print -rl -- "${SIM_ROWS[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE "$SIM_FZF" "${picker_args[@]}")" || result=$?
    if (( allow_back && (result == 0 || result == 1) )) && [[ "${output%%$'\n'*}" == left ]]; then
        return 10
    fi
    if (( result == 130 || result == 1 )); then
        SIM_CANCELLED=1
        return 130
    fi
    if (( result != 0 )); then
        sim_log "✖ 选择器执行失败（退出码 ${result}），未创建模拟器。"
        return "$result"
    fi
    if (( allow_back )); then
        key="${output%%$'\n'*}"
        [[ "$key" == left ]] && return 10
        [[ -z "$key" ]] || return 1
        [[ "$output" == *$'\n'* ]] || return 1
        output="${output#*$'\n'}"
    fi
    SIM_SELECTED_ROW="$output"
    if [[ -z "$SIM_SELECTED_ROW" ]]; then
        SIM_CANCELLED=1
        return 130
    fi
    if (( ${SIM_ROWS[(Ie)$SIM_SELECTED_ROW]} == 0 )); then
        sim_log '✖ 选择结果不属于当前清单，已停止。'
        return 1
    fi
}
# 保留完整型号并优先推荐可搭配已装系统的型号，选定后只列匹配该型号的系统。
sim_select_combination() {
    local devices="" runtimes="" total=0 matched=0 result=0
    local -a all_rows matched_rows
    if ! devices="$(sim_data preferred-devicetypes "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法解析设备型号：${devices}"
        return 1
    fi
    if [[ -z "$devices" ]]; then
        sim_log '✖ 当前 Xcode 没有 iPhone / iPad 设备类型，请检查 Xcode 组件后重试。'
        return 1
    fi
    if ! runtimes="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法解析 Runtime：${runtimes}"
        return 1
    fi
    if [[ -z "$runtimes" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime。请在 Xcode → Settings → Components 安装后重试。'
        return 1
    fi
    all_rows=("${(@f)runtimes}")
    total=${#all_rows}
    while true; do
        sim_choose_row '选择 iPhone / iPad 型号' "$devices" || return $?
        SIM_DEVICE_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
        SIM_DEVICE_ID="${SIM_SELECTED_ROW#*$'\t'}"
        if ! runtimes="$(sim_data compatible-runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" "$SIM_RUN_DIR/devicetypes.json" "$SIM_DEVICE_ID" 2>&1)"; then
            sim_log "✖ 无法匹配所选型号的系统：${runtimes}"
            return 1
        fi
        if [[ -z "$runtimes" ]]; then
            sim_log "✖ ${SIM_DEVICE_NAME} 没有可搭配的已安装 iOS 系统：本机 ${total} 个已装 iOS 系统都不支持该型号。"
            sim_log '➤ 请在 Xcode 安装该型号可用的 Runtime，或重新选择其它型号；未创建模拟器。'
            return 2
        fi
        matched_rows=("${(@f)runtimes}")
        matched=${#matched_rows}
        # 明确列出匹配数量，避免把本机全部系统当成该型号的可选项。
        sim_log "➤ ${SIM_DEVICE_NAME}：本机已装 ${total} 个 iOS 系统，其中 ${matched} 个匹配该型号。"
        if (( total > matched )); then
            sim_log "➤ 已排除 $(( total - matched )) 个不支持该型号的已装系统，未被 Xcode 明确列出的系统标注为“（未确认支持）”。"
        fi
        sim_log '➤ 已确认支持的最新系统排首位，回车采用首项。'
        result=0
        sim_choose_row '选择 iOS 系统版本' "$runtimes" 1 || result=$?
        if (( result == 10 )); then
            SIM_RUNTIME_NAME=""
            SIM_RUNTIME_ID=""
            sim_log '↩ 已返回型号选择，未创建模拟器。'
            continue
        fi
        (( result == 0 )) || return "$result"
        SIM_RUNTIME_NAME="${SIM_SELECTED_ROW%%$'\t'*}"
        SIM_RUNTIME_ID="${SIM_SELECTED_ROW#*$'\t'}"
        return 0
    done
}
# 创建前刷新已有名称，避开同秒操作或遗留同名设备。
sim_prepare_unique_name() {
    local base="${SIM_DEVICE_NAME}@$(/bin/date '+%Y.%m.%d %H:%M:%S')-${$}" output=""
    if ! sim_run_to_file "$SIM_RUN_DIR/devices.json" 30 /usr/bin/xcrun simctl list devices --json; then
        sim_log '✖ 刷新已有设备失败，已停止创建。'
        sim_log "$(<"$SIM_RUN_DIR/devices.json")"
        return 1
    fi
    if ! output="$(sim_data unique-name "$SIM_RUN_DIR/devices.json" "$base" 2>&1)"; then
        sim_log "✖ 无法确认唯一设备名：${output}"
        return 1
    fi
    SIM_NAME="$output"
}
# 明确展示即将创建的组合；任意非空输入都取消。
sim_confirm_creation() {
    local answer=""
    sim_log "➤ 设备：${SIM_DEVICE_NAME}"
    sim_log "➤ 系统：${SIM_RUNTIME_NAME}"
    sim_log "➤ 新名称：${SIM_NAME}"
    if [[ "$SIM_RUNTIME_NAME" == *未确认支持* ]]; then
        sim_log '⚠ 所选系统未被 Xcode 明确列为支持该型号，创建可能失败；失败时输入 r 可重新选择。'
    fi
    sim_log '➤ 型号与系统分别列出，组合是否受支持由 Xcode 创建命令最终校验；不支持时需输入 r 才重新选择。'
    if ! IFS= read -r "?直接回车创建并启动；输入任意字符取消：" answer || [[ -n "$answer" ]]; then
        SIM_CANCELLED=1
        return 130
    fi
}
# 只新增并启动选定设备；创建结果不明确时停止，避免重试产生重复设备。
sim_create_and_boot() {
    local output="$SIM_RUN_DIR/command.out" result=0 value=""
    sim_log "➤ 正在创建：${SIM_NAME}"
    sim_run_to_file "$output" 30 /usr/bin/xcrun simctl create "$SIM_NAME" "$SIM_DEVICE_ID" "$SIM_RUNTIME_ID" || result=$?
    value="$(<"$output")"
    if (( result != 0 )); then
        if (( result != 124 )) && [[ "$value" == *'Incompatible device'* ]]; then
            sim_log "⚠ 当前设备 / 系统组合不受支持：${value}"
            return 2
        fi
        sim_log "✖ 创建未成功确认（退出码 ${result}）：${value}"
        sim_log '➤ 已停止，未自动重试。若命令曾超时，请先检查 Simulator 设备列表。'
        return 1
    fi
    if [[ ! "$value" =~ '^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$' ]]; then
        sim_log "✖ 创建命令返回的 UDID 无效：${value}"
        sim_log '➤ 已停止，未自动重试；请检查 Simulator 设备列表。'
        return 1
    fi
    SIM_UDID="$value"
    sim_log "✔ 模拟器已创建：${SIM_NAME}（${SIM_UDID}）"
    if ! sim_run_to_file "$output" 30 /usr/bin/xcrun simctl boot "$SIM_UDID"; then
        sim_log "✖ 启动失败：$(<"$output")"
        sim_log "➤ 新设备已保留。可稍后运行：xcrun simctl boot ${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 15 /usr/bin/open -a "$SIM_APP"; then
        sim_log "✖ 无法打开模拟器界面：$(<"$output")"
        sim_log "➤ 已保留设备：${SIM_UDID}"
        return 1
    fi
    if ! sim_run_to_file "$output" 120 /usr/bin/xcrun simctl bootstatus "$SIM_UDID"; then
        sim_log "⚠ 设备已创建并发起启动，但尚未确认完成：$(<"$output")"
        sim_log "➤ 请在 Simulator 查看 ${SIM_NAME}（${SIM_UDID}）。"
        return 1
    fi
    sim_log "✔ 新模拟器已完成启动：${SIM_NAME}"
    if [[ "$SIM_APP_KIND" == com.apple.dt.Devices ]]; then
        sim_log "➤ 已打开 Device Hub；可按设备名选中 ${SIM_NAME}（${SIM_UDID}）。"
    fi
}
# 仅在明确不兼容且用户输入 r / R 后重选，连续回车不会再弹出列表。
sim_confirm_reselection() {
    local answer=""
    if IFS= read -r "?输入 r 重新选择型号和系统；直接回车或其它输入停止：" answer && [[ "$answer" == [rR] ]]; then
        return 0
    fi
    sim_log '➤ 已停止，未重复选择或再次创建模拟器。'
    return 1
}
# 交互取消正常返回；成功或普通失败均结束，重选必须再次明确发起。
sim_interactive_loop() {
    local result=0
    while true; do
        result=0
        sim_select_combination || result=$?
        if (( result == 130 )); then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        elif (( result == 2 )); then
            # 所选型号没有可搭配系统时同不兼容组合一样，只有明确输入 r 才重选。
            sim_confirm_reselection || return 1
            continue
        elif (( result != 0 )); then
            return "$result"
        fi
        sim_prepare_unique_name || return $?
        if ! sim_confirm_creation; then
            sim_log '➤ 已取消，未创建模拟器。'
            return 0
        fi
        result=0
        sim_create_and_boot || result=$?
        if (( result == 2 )); then
            sim_confirm_reselection || return 1
            continue
        fi
        return "$result"
    done
}
# 显示独立运行接口，不加载或修改模拟器环境。
sim_show_help() {
    sim_log "用法：/bin/zsh \"${SCRIPT_PATH}\" [--help | --check]"
    sim_log '  无参数   在可交互终端中选择并新建一个模拟器。'
    sim_log '  --help   显示帮助；不读取 Xcode 或创建日志。'
    sim_log '  --check  只读体检 Xcode / simctl，并列出完整机型、可搭配系统的机型数量及每个可用 iOS 系统支持的机型数。'
    sim_log '来源：JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command。'
}
# 体检完整机型和可用系统清单，不把独立列出的两者误报为全部兼容。
sim_report_catalog() {
    local rows="" devices="" row="" summary="" rest=""
    local matched=0 unmatched=0
    local -a device_rows
    if ! rows="$(sim_data runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ Runtime 数据无效：${rows}"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        sim_log '✖ 没有本机可用的 iOS Runtime；本次未创建或下载。'
        return 1
    fi
    if ! devices="$(sim_data devicetypes "$SIM_RUN_DIR/devicetypes.json" 2>&1)"; then
        sim_log "✖ 设备型号数据无效：${devices}"
        return 1
    fi
    if [[ -z "$devices" ]]; then
        sim_log '✖ 当前 Xcode 没有 iPhone / iPad 设备类型。'
        return 1
    fi
    device_rows=("${(@f)devices}")
    if ! summary="$(sim_data catalog-summary "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法汇总机型与系统的匹配关系：${summary}"
        return 1
    fi
    rest="${${summary%%$'\n'*}#*$'\t'}" # 跳过 models 后的机型总数，只取可搭配与无可搭配两项。
    rest="${rest#*$'\t'}"
    matched="${rest%%$'\t'*}"
    unmatched="${rest#*$'\t'}"
    sim_log "✔ 完整机型清单：${#device_rows} 个 iPhone / iPad（不按 Runtime 隐藏型号；其中 ${matched} 个已有可搭配系统，${unmatched} 个本机无可搭配系统）"
    for row in "${(@f)${summary#*$'\n'}}"; do
        [[ "${row%%$'\t'*}" == runtime ]] || continue
        rest="${row#*$'\t'}"
        if [[ "${rest#*$'\t'}" == -1 ]]; then
            sim_log "✔ 可用系统：${rest%%$'\t'*}（支持机型数未知）"
        else
            sim_log "✔ 可用系统：${rest%%$'\t'*}（支持 ${rest#*$'\t'} 个机型）"
        fi
    done
    sim_report_default_combination || return $?
    sim_log '➤ 首项优先采用已确认支持的组合；元数据缺失保留候选，仍由 simctl create 最终校验。'
    sim_log '✔ 只读体检完成；未创建、启动、关闭或删除模拟器。'
}
# 只读展示两次回车将选择的组合，便于在目标电脑核对默认值。
sim_report_default_combination() {
    local devices="" device="" runtimes="" runtime=""
    if ! devices="$(sim_data preferred-devicetypes "$SIM_RUN_DIR/devicetypes.json" "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" 2>&1)"; then
        sim_log "✖ 无法推荐默认型号：${devices}"
        return 1
    fi
    device="${devices%%$'\n'*}"
    if ! runtimes="$(sim_data compatible-runtimes "$SIM_RUN_DIR/runtimes.json" "$(/usr/bin/uname -m)" "$SIM_RUN_DIR/devicetypes.json" "${device#*$'\t'}" 2>&1)"; then
        sim_log "✖ 无法推荐默认系统：${runtimes}"
        return 1
    fi
    if [[ -z "$runtimes" ]]; then
        sim_log '✖ 当前型号与已装系统没有可推荐的组合，请在 Xcode 安装对应 Runtime。'
        return 1
    fi
    runtime="${runtimes%%$'\n'*}"
    sim_log "✔ 回车首选组合：${device%%$'\t'*} / ${runtime%%$'\t'*}"
}
# 将帮助、只读体检与交互创建路由到各自流程，并传播失败状态。
sim_run_requested_action() {
    if [[ "$SIM_MODE" == help ]]; then
        sim_show_help
        return 0
    fi
    sim_initialize_runtime
    sim_check_environment || return $?
    if [[ "$SIM_MODE" == interactive ]]; then
        sim_check_selector || return $?
    fi
    sim_load_catalog || return $?
    if [[ "$SIM_MODE" == check ]]; then
        sim_report_catalog
    else
        sim_interactive_loop
    fi
}
# <<< Jobs iOS simulator core <<<

# 首屏说明独立初始化入口的清场与依赖策略，确认前不执行探测或写入。
show_script_intro_and_wait() {
    sim_prepare_context
    sim_intro_line title '━━━━━━━━━━ 双击初始化 iOS 模拟器 ━━━━━━━━━━'
    sim_intro_line body "当前脚本：${SCRIPT_PATH}"
    sim_intro_line body '1、完整型号中优先显示有可搭配系统的机型，无可搭配系统的机型带标注；选完型号后只列匹配该型号的系统；一路回车采用首选组合，创建并启动新模拟器。'
    sim_intro_line body '2、初始化前按原策略检查构建与模拟器状态；强制关闭现有设备必须输入 YES。'
    sim_intro_line body '3、自检 Homebrew / fzf；缺少时安装，已有依赖的升级回车跳过、输入任意字符执行。'
    sim_intro_line body '4、Ctrl+C 随时停止，系统选择时 ← 返回型号，Esc / Ctrl+C 取消，最终回车才创建；--help / --check 只读。'
    sim_intro_line body "日志位置：${LOG_FILE}（确认后创建；只读入口不写日志）"
    sim_confirm_entry "$@"
}
# 只读请求先分流；独立入口保留清场和依赖自检，再进入相同创建核心。
run_initialization_requested_action() {
    if [[ "$SIM_MODE" != interactive ]]; then
        sim_run_requested_action
        return $?
    fi
    sim_initialize_runtime
    sim_check_environment || return $?
    cleanup_simulator_background_safely || return $?
    install_homebrew || return $?
    install_fzf || return $?
    sim_check_selector || return $?
    sim_load_catalog || return $?
    sim_interactive_loop
}
# 编排独立入口自述、初始化及与右键入口相同的模拟器创建业务。
main() {
    show_script_intro_and_wait "$@" # 首先展示本入口真实影响，并完成只读分流或终端确认。
    run_initialization_requested_action # 保留独立初始化策略，使用相同核心选择并创建模拟器。
}

main "$@"
