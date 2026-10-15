#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🔍Git依据提交日志关键字查找.command
# - 核心用途：执行“🔍Git依据提交日志关键字查找”对应的 Git / Sourcetree 自动化操作。
# - 影响范围：可能修改当前仓库、工作区、分支、菜单配置或 Git 索引。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

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
  brew_bin="$(jobs_brew_find)" || { error_echo "没有健康 Homebrew，停止激活。"; return 1; }
  JOBS_HOMEBREW_BIN="$brew_bin"
  jobs_brew_activate || { error_echo "Homebrew 激活或命令层复检失败。"; return 1; }

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\"" || return 1
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

  if ! brew_bin="$(jobs_brew_find)"; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || exit 1
    return 0
  fi

  activate_homebrew_shellenv || exit 1
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update || exit 1
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
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】🔍Git依据提交日志关键字查找.command' | jobs_intro_style title
  print -r -- '核心用途：执行“🔍Git依据提交日志关键字查找”对应的 Git 自动化操作。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ================================== git-branch-origin-from-desc ==================================
  # 仅通过 commit 描述（subject）推断：当前分支最初从哪个分支切出来
  # - 自动：匹配 “Merge … into <当前分支> / 合并…到 <当前分支>”
  # - 回退：交互输入关键字（或用 fzf 选择）在提交描述里定位“锚点提交”
  # ================================================================================================

  set -e
  set -u
  set -o pipefail

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

  # ---------- 彩色 & 日志 ----------
  SCRIPT_BASENAME="${0:t:r}"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
  # 屏幕+日志（stdout），用于常规输出
  log()            { local msg="$1"; printf '%b\n' "$msg"; printf '%b\n' "$msg" >> "$LOG_FILE"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  gray_echo()      { log "\033[0;90m$1\033[0m"; }
  # 只写 TTY+日志（不碰 stdout），用于需要把 stdout 当“返回值”的函数
  tty_log()     { local msg="$1"; printf '%b\n' "$msg" > /dev/tty; printf '%b\n' "$msg" >> "$LOG_FILE"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info_tty()    { tty_log "\033[1;34mℹ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success_tty() { tty_log "\033[1;32m✔ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn_tty()    { tty_log "\033[1;33m⚠ $1\033[0m"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  error_tty()   { tty_log "\033[1;31m✖ $1\033[0m"; }
  # ---------- 横幅/自述 ----------
  show_banner() {
    cat <<'EOF' | jobs_intro_style auto
  ┌──────────────────────────────────────────────────────────────┐
  │  git-branch-origin-from-desc (zsh)                           │
  │  自动：匹配 “Merge … into <当前分支> / 合并…到 <当前分支>”     │
  │  回退：输入关键字（或 fzf 选择）在提交描述里定位锚点          │
  └──────────────────────────────────────────────────────────────┘
EOF
  }
  # 展示脚本用途和影响范围，并在执行前等待用户确认。
  intro() {
    show_banner
    print -r -- "按回车继续（Ctrl+C 退出）..." > /dev/tty
    read -r _ < /dev/tty || true
  }
  # ---------- 去 ANSI ----------
  strip_ansi() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'; }
  # ---------- 路径处理 ----------
  sanitize_path() {
    local p; p="$(print -r -- "$1" | strip_ansi)"
    # 去首尾空白
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    # 去包裹引号
    p="${p%\"}"; p="${p#\"}"
    p="${p%\'}"; p="${p#\'}"
    # 去掉 CR（拖拽/某些终端会混入 \r）
    p="${p//$'\r'/}"
    # 展开 ~
    [[ "$p" == "~"* ]] && p="${p/#\~/$HOME}"
    # 去尾 /
    [[ "$p" != "/" ]] && p="${p%/}"
    print -r -- "$p"
  }
  # 封装 abs_path 对应的独立处理逻辑。
  abs_path() {
    local p; p="$(sanitize_path "$1")"; [[ -z "$p" ]] && return 1
    if command -v realpath >/dev/null 2>&1; then realpath "$p" 2>/dev/null || return 1
    else
      if [[ -d "$p" ]]; then ( builtin cd -- "$p" 2>/dev/null && pwd -P ) || return 1
      elif [[ -f "$p" ]]; then ( builtin cd -- "${p:h}" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "${p:t}" ) || return 1
      else return 1; fi
    fi
  }
  # ---------- Git 判定 ----------
  is_git_repo() {
    local dir="$1"
    # 工作副本：.git 目录或 .git 文件（worktree 等）
    [[ -d "$dir/.git" || -f "$dir/.git" ]] && return 0
    # 裸仓库（可选）
    [[ -f "$dir/HEAD" && -d "$dir/objects" && -d "$dir/refs" ]] && return 0
    return 1
  }
  # ---------- 询问直到 Git 仓库（stdout 只输出路径） ----------
  ask_git_repo() {
    local default_dir="$1"
    local candidate="" ap=""

    while :; do
      print -r -- "📂 请拖入/输入 Git 仓库目录（直接回车 = 使用脚本所在目录）：" > /dev/tty
      print -n -- "> " > /dev/tty
      IFS= read -r candidate < /dev/tty || candidate=""
      candidate="$(sanitize_path "$candidate")"

      # 选默认或输入
      if [[ -z "$candidate" ]]; then
        ap="$(abs_path "$default_dir" || true)"
      else
        ap="$(abs_path "$candidate" || true)"
      fi

      # 校验
      if [[ -n "${ap:-}" && -d "$ap" ]]; then
        if is_git_repo "$ap"; then
          success_tty "确认 Git 仓库：$ap"
          typeset -g SCRIPT_DIR="$ap"   # ← 关键：强制写全局，避免被上层 local 遮蔽
          # 进入仓库目录（解析符号链接，安全处理空格/中文）
          builtin cd -P -- "$SCRIPT_DIR" || { print -ru2 -- "✖ 无法进入目录：$SCRIPT_DIR"; exit 1; }
          print -r -- "📍 当前目录：$PWD" > /dev/tty
          return 0
        else
          error_tty "不是 Git 仓库：$ap"
        fi
      else
        error_tty "无效路径：${candidate:-<空>}"
      fi
    done
  }
  # ---------- 当前分支 ----------
  current_branch_name() { git -C "$1" rev-parse --abbrev-ref HEAD; }
  # ---------- 解析 subject：输出 "<SRC> <DST>"（Perl，避免 awk 引号坑） ----------
  parse_src_dst_from_subject() {
    perl -ne "
      s/[“”\"]/\'/g;                          # 中文/双引号 → 单引号
      if (/[Mm]erge\\s+branch\\s+'([^']+)'\\s+into\\s+'?([^' ]+)'?/){ print \"\$1 \$2\\n\"; exit }
      if (/[Mm]erge\\s+([^ ]+)\\s+into\\s+([^ ]+)/){ print \"\$1 \$2\\n\"; exit }
      if (/合并分支\\s+'([^']+)'\\s+到\\s+([^ ]+)/){ print \"\$1 \$2\\n\"; exit }
      if (/将\\s+([^ ]+)\\s+合并到\\s+([^ ]+)/){ print \"\$1 \$2\\n\"; exit }
    "
  }
  # ---------- 自动：扫描日志（取“最早”命中） ----------
  find_origin_from_desc() {
    local repo="$1" cur="$2"
    git -C "$repo" log --reverse --pretty=format:'%s' \
    | while IFS= read -r subject; do
        local pair src dst
        pair="$(printf '%s' "$subject" | parse_src_dst_from_subject || true)"
        if [[ -n "$pair" ]]; then
          src="${pair%% *}"; dst="${pair#* }"
          if [[ "$dst" == "$cur" ]]; then print -r -- "$src"; exit 0; fi
        fi
      done
    return 1
  }
  # ---------- 回退：锚点关键字模式（可用 fzf 选择） ----------
  has_fzf() { command -v fzf >/dev/null 2>&1; }
  # 封装 anchor_search 对应的独立处理逻辑。
  anchor_search() {
    local repo="$1" kw="$2" scope="${3:-fp}" extra=()
    [[ "$scope" == "fp" ]] && extra+=( --first-parent )
    git -C "$repo" log --no-color --date=iso --pretty=format:'%H%x09%ad%x09%s' "${extra[@]}" HEAD | grep -F -- "$kw" || true
  }
  # 执行已经拆分完成的独立业务步骤。
  run_anchor_interactive() {
    local repo="$1" kw=""
    if has_fzf; then
      local subjects; subjects="$(git -C "$repo" log --no-color --pretty=format:'%s' HEAD | awk 'NF' | awk '!seen[$0]++')"
      print -r -- "🔎 选择/输入锚点关键字（fzf，回车确认；Esc 取消）：" > /dev/tty
      kw="$(print -r -- "$subjects" | fzf --ansi --height=80% --reverse --prompt='关键字： ' --header=$'↑↓选择，输入过滤；回车确定')" || kw=""
    fi
    if [[ -z "$kw" ]]; then
      print -r -- "请输入用于匹配提交描述的关键字（例如：JobsBranch@新葡京（蓝）），直接回车退出：" > /dev/tty
      print -n -- "> " > /dev/tty
      IFS= read -r kw < /dev/tty || kw=""
      kw="$(sanitize_path "$kw")"
    fi
    [[ -z "$kw" ]] && { warn_tty "未输入关键字，已跳过。"; return 1; }

    local hits; hits="$(anchor_search "$repo" "$kw" fp)"
    [[ -z "$hits" ]] && hits="$(anchor_search "$repo" "$kw" all)"
    [[ -z "$hits" ]] && { warn_tty "关键字在提交描述中未命中。"; return 1; }

    print -r -- "选择命中：1) 最早（默认）  2) 最近" > /dev/tty
    print -n -- "> " > /dev/tty
    local sel; IFS= read -r sel < /dev/tty || sel=""
    local pick
    if [[ "$sel" == "2" ]]; then pick="$(print -r -- "$hits" | tail -n1)"; else pick="$(print -r -- "$hits" | head -n1)"; fi

    local H D S; IFS=$'\t' read -r H D S <<< "$pick"
    success_tty "锚点命中：$H  $D  $S"
    git -C "$repo" show -s --format=$'哈希: %H\n作者: %an <%ae>\n时间: %ad\n标题: %s' --date=iso "$H" > /dev/tty
    return 0
  }
  # ---------- 主流程 ----------
  main() {
    : > "$LOG_FILE" 2>/dev/null || true
    intro

    info_echo "脚本所在目录：$SCRIPT_DIR"
    export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

    # 1) 让用户选择仓库目录（内部会设置 SCRIPT_DIR 并且 cd -P 进去）
    ask_git_repo "$SCRIPT_DIR"

    # 2) 统一用 SCRIPT_DIR 作为仓库根
    local REPO_DIR="$SCRIPT_DIR"
    local CUR_BRANCH; CUR_BRANCH="$(current_branch_name "$REPO_DIR")"
    info_echo "当前分支：$CUR_BRANCH"

    # 3) 自动推断
    local ORIGIN=""
    if ORIGIN="$(find_origin_from_desc "$REPO_DIR" "$CUR_BRANCH")"; then
      success_echo "推断结果：'$CUR_BRANCH' 可能最初从 '$ORIGIN' 切出（依据 commit 描述）"
      gray_echo "注：自动模式依赖“Merge … into … / 合并…到 …”类语句。"
      highlight_echo "日志：$LOG_FILE"
    else
      warn_echo "自动模式未命中。进入锚点关键字模式。"
      if run_anchor_interactive "$REPO_DIR"; then
        highlight_echo "日志：$LOG_FILE"
      else
        highlight_echo "日志：$LOG_FILE"
        exit 2
      fi
    fi
  }

  if [[ "${(%):-%x}" == "$0" ]]; then
    main "$@"
  fi

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
