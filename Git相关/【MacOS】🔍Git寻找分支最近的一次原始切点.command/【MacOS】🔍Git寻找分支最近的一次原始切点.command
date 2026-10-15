#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🔍Git寻找分支最近的一次原始切点.command
# - 核心用途：执行“🔍Git寻找分支最近的一次原始切点”对应的 Git / Sourcetree 自动化操作。
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
  print -r -- '脚本名称：【MacOS】🔍Git寻找分支最近的一次原始切点.command' | jobs_intro_style title
  print -r -- '核心用途：执行“🔍Git寻找分支最近的一次原始切点”对应的 Git 自动化操作。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前仓库、工作区、分支或 Git 索引。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ================================== git-branch-origin-from-branch ==================================
  # 交互选择一个分支，推断它“最初从哪条分支切出来”
  # - 先 reflog（本机创建过就能直接看到来源）
  # - 再拓扑：在所有分支里排名最近父分支，输出分叉点和“切出后首个独有提交”
  # ================================================================================================

  export GIT_PAGER=cat
  export PAGER=cat

  set -e
  set -u
  set -o pipefail
  # 统一的 git 调用：固定仓库目录 + 禁用分页器
  G() { git -C "$SCRIPT_DIR" --no-pager "$@"; }

  # --- PATH（双击 .command 时常常很干净） ---
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # --- 初始脚本目录（bash/zsh 通吃） ---
  SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd -P)"
  # ---------- 简单输出（到 TTY，避免污染 stdout） ----------
  say()      { print -r -- "$*" > /dev/tty; }
  # 封装 ok 对应的独立处理逻辑。
  ok()       { say "✅ $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info()     { say "ℹ️  $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn()     { say "⚠️  $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  err()      { say "❌ $*"; }
  # ---------- 去 ANSI & 路径清理 ----------
  _strip_ansi() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'; }
  # 封装 sanitize_path 对应的独立处理逻辑。
  sanitize_path() {
    local p; p="$(print -r -- "${1:-}" | _strip_ansi)"
    p="${p//$'\r'/}"                                            # 去 CR（拖拽常见）
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"  # 去首尾空白
    p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"               # 去引号
    [[ "$p" == "~"* ]] && p="${p/#\~/$HOME}"                        # 展开 ~
    [[ "$p" != "/" ]] && p="${p%/}"
    print -r -- "$p"
  }
  # 封装 abs_path 对应的独立处理逻辑。
  abs_path() {
    local p; p="$(sanitize_path "$1")"; [[ -z "$p" ]] && return 1
    if [[ -d "$p" ]]; then ( builtin cd -P -- "$p" 2>/dev/null && pwd -P ) || return 1
    elif [[ -f "$p" ]]; then ( builtin cd -P -- "${p:h}" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "${p:t}" ) || return 1
    else return 1
    fi
  }
  # ---------- Git 仓库判定（只认工作副本：.git 目录/文件） ----------
  is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" || -f "$dir/.git" ]] && return 0
    return 1
  }
  # ---------- 询问直到拿到 Git 仓库，并 cd 进去 ----------
  ask_git_repo() {
    local default_dir="$1" candidate ap
    while :; do
      say "📂 请拖入/输入 Git 仓库目录（直接回车 = 使用脚本所在目录）："
      print -n -- "> " > /dev/tty
      IFS= read -r candidate < /dev/tty || candidate=""
      candidate="$(sanitize_path "$candidate")"

      if [[ -z "$candidate" ]]; then
        ap="$(abs_path "$default_dir" || true)"
      else
        ap="$(abs_path "$candidate" || true)"
      fi

      if [[ -n "${ap:-}" && -d "$ap" ]]; then
        if is_git_repo "$ap"; then
          typeset -g SCRIPT_DIR="$ap"
          builtin cd -P -- "$SCRIPT_DIR" || { err "无法进入目录：$SCRIPT_DIR"; exit 1; }
          ok "确认 Git 仓库：$SCRIPT_DIR"
          say "📍 当前目录：$PWD"
          return 0
        else
          err "不是 Git 仓库：$ap"
        fi
      else
        err "无效路径：${candidate:-<空>}"
      fi
    done
  }
  # ---------- 分支选择（支持 fzf，也可手输） ----------
  list_all_branches() {
    git -C "$SCRIPT_DIR" for-each-ref --format='%(refname:short)' refs/heads refs/remotes \
    | grep -v '^origin/HEAD$' | sort -u
  }
  # 封装 pick_target_branch 对应的独立处理逻辑。
  pick_target_branch() {
    local choice=""
    if command -v fzf >/dev/null 2>&1; then
      choice="$(list_all_branches | fzf --height=80% --reverse --prompt='选择要分析的分支： ')" || choice=""
    fi
    if [[ -z "$choice" ]]; then
      say "请输入要分析的分支名（例如：Hi 或 origin/Hi）："
      print -n -- "> " > /dev/tty
      IFS= read -r choice < /dev/tty || choice=""
    fi
    [[ -z "$choice" ]] && { err "未输入分支名"; exit 2; }
    print -r -- "$choice"
  }
  # ---------- reflog：本机创建过就能看到来源 ----------
  origin_from_reflog() {
    # 仅对“本地分支”有效；remote 分支没有 reflog
    local br="$1"
    br="${br#refs/heads/}"
    br="${br#origin/}"                 # 用户可能输入 origin/xxx；reflog 只看本地
    local line src
    line="$(git -C "$SCRIPT_DIR" log -g --date=iso --format='%gd|%gs' "refs/heads/$br" 2>/dev/null | tail -n1 || true)"
    [[ -z "$line" ]] && return 1
    # 典型格式：
    #   branch: Created from <src>
    #   checkout: moving from <src> to <br>
    src="$(sed -nE 's/.*branch: Created from ([^ ]+).*/\1/p' <<<"${line#*|}")"
    [[ -z "$src" ]] && src="$(sed -nE 's/.*checkout: moving from ([^ ]+) to .*/\1/p' <<<"${line#*|}")"
    [[ -n "$src" ]] || return 1
    print -r -- "$src|$line"
  }
  # ---------- 拓扑：fork-point / merge-base ----------
  _fork_point() {
    local base="$1" head="$2" fk=""
    fk="$(git -C "$SCRIPT_DIR" merge-base --fork-point "$base" "$head" 2>/dev/null || true)"
    [[ -z "$fk" ]] && fk="$(git -C "$SCRIPT_DIR" merge-base "$base" "$head" 2>/dev/null || true)"
    print -r -- "$fk"
  }
  # 封装 first_unique_after_fork 对应的独立处理逻辑。
  first_unique_after_fork() {
    local fork="$1" head="$2"
    git -C "$SCRIPT_DIR" rev-list --ancestry-path "$fork..$head" --reverse | head -n1 || true
  }
  # ---------- 在所有分支里对“父分支”打分并取 Top1 ----------
  # 在所有分支里对“父分支”打分并取 Top1（输出一行，使用真实的 TAB 分隔）
  # 在所有分支里对“父分支”打分并取 Top1（输出一行，字段用真实 TAB 分隔）
  rank_parent_for_target() {
    local target="$1"
    list_all_branches | while IFS= read -r br; do
      [[ -z "$br" || "$br" == "$target" ]] && continue

      local fk ct ha ba lr behind ahead score
      fk="$(_fork_point "$br" "$target")"       || continue
      [[ -z "$fk" ]] && continue

      ct="$(G show -s --format=%ct "$fk" 2>/dev/null || echo 0)"
      ha="$(G rev-list --first-parent "$fk..$target" --count 2>/dev/null || echo 0)"
      ba="$(G rev-list --first-parent "$fk..$br"     --count 2>/dev/null || echo 0)"
      lr="$(G rev-list --left-right --count "$br...$target" 2>/dev/null || echo "0 0")"
      behind="${lr%% *}"; ahead="${lr##* }"

      # 评分：越新越好（ct），父分支在 fork 后越“干净”越好（ba）
      score=$(( ct * 1000 - ba * 50 ))

      # 关键：printf 打印真实 TAB
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$score" "$ct" "$br" "$fk" "$ha" "$ba" "$ahead" "$behind"
    done | sort -nr -k1,1 | head -n1
  }
  # 封装 session_once 对应的独立处理逻辑。
  session_once() {
    # ① 选目标分支
    local TARGET; TARGET="$(pick_target_branch)"
    info "目标分支：$TARGET"

    # ② reflog 直接线索（若该分支在本机创建过）
    local refl src when msg
    if refl="$(origin_from_reflog "$TARGET")"; then
      src="${refl%%|*}"; msg="${refl#*|}"; when="${msg%%|*}"
      ok   "reflog：$TARGET 最初来自 '$src'"
      say  "🕒 创建记录：${when#*@\{}"
      say  "📝 线索：${msg#*|}"
    else
      warn "本机 reflog 无法确定 $TARGET 的来源（可能不是在本机创建的）。"
    fi

    # ③ 拓扑：最近父分支 + 分叉点
    local row; row="$(rank_parent_for_target "$TARGET")" || { err "无法通过拓扑推断父分支。"; return 1; }
    local SCORE CT PARENT FORK HA BA AHEAD BEHIND
    IFS=$'\t' read -r SCORE CT PARENT FORK HA BA AHEAD BEHIND <<< "$row"

    ok "推测父分支：$PARENT"
    say "── 分叉点（fork-point / merge-base）：$FORK"
    G show -s --format=$'哈希: %H\n作者: %an <%ae>\n时间: %ad\n标题: %s' --date=iso "$FORK" > /dev/tty

    # ④ 切出后首个独有提交
    local FU; FU="$(G rev-list --ancestry-path "$FORK..$TARGET" --reverse | head -n1 || true)"
    if [[ -n "$FU" ]]; then
      say
      info "切出后首个独有提交："
      G show -s --format=$'哈希: %H\n作者: %an <%ae>\n时间: %ad\n标题: %s' --date=iso "$FU" > /dev/tty
    fi

    # ⑤ 统计（重新算一次，避免字段黏连）
    local lr; lr="$(G rev-list --left-right --count "$PARENT...$TARGET" 2>/dev/null || echo "0 0")"
    local BEH="${lr%% *}" AH="${lr##* }"
    say
    say "📊 统计：相对父分支 ahead=$AH, behind=$BEH；从分叉点到目标分支（first-parent）提交数=$HA"
    [[ -n "${src:-}" ]] && say "📎 备注：reflog 显示初始来源为 '$src'（若与拓扑不一致，请以实际工作流为准）。"
  }
  # ---------- 主流程 ----------
  main() {
    say "┌──────────────────────────────────────────────────────────────┐"
    say "│  选择一个分支，推断它最初从哪条分支切出来                     │"
    say "└──────────────────────────────────────────────────────────────┘"
    say "按回车继续（Ctrl+C 退出）..."
    read -r _ < /dev/tty || true

    info "脚本所在目录：$SCRIPT_DIR"
    # 第一次先选仓库（函数里会设置 SCRIPT_DIR 并 cd 进去）
    ask_git_repo "$SCRIPT_DIR"

    while :; do
      session_once     # 跑一轮

      say
      say "继续吗？（回车=继续分析其它分支｜c=更换仓库｜q=退出）"
      print -n -- "> " > /dev/tty
      local ans; IFS= read -r ans < /dev/tty || ans="q"
      case "$ans" in
        q|Q) break ;;
        c|C) ask_git_repo "$SCRIPT_DIR" ;;   # 允许更换仓库后继续
        *)   ;;                              # 默认继续，用当前仓库再选分支
      esac
    done
  }

  # ---------- 入口 ----------
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
