#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】📦双击自动生成ipa文件.command
# - 核心用途：执行“📦双击自动生成ipa文件”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
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
  print -r -- '脚本名称：【MacOS】📦双击自动生成ipa文件.command' | jobs_intro_style title
  print -r -- '核心用途：执行“📦双击自动生成ipa文件”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  IPA_FZF_BIN="$(command -v fzf 2>/dev/null || true)"
  IPA_LAST_PROJECT=""
  IPA_SELECTED_PROJECT=""
  IPA_SELECTED_SCHEME=""
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
  setopt NO_NOMATCH
  set -euo pipefail

  # ================================== 默认配置 ==================================
  CONFIG="Release"
  OUT_DIR="${HOME}/Desktop"
  PROJECT_PATH=""
  SCHEME=""
  TARGET=""
  CONFIRM="0"
  LOG_FILE="/tmp/$(basename "$0").log"
  # ================================== 输出 + 日志 ==================================
  _color() { local c="$1"; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info_echo()    { _color "34" "ℹ️  $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  success_echo() { _color "32" "✅ $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn_echo()    { _color "33" "⚠️  $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  err_echo()     { _color "31" "❌ $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  log() {
    local ts
    ts="$(/bin/date '+%F %T' 2>/dev/null || echo '0000-00-00 00:00:00')"
    printf "%s %s\n" "$ts" "$*" >> "$LOG_FILE"
  }
  # 封装 on_error 对应的独立处理逻辑。
  on_error() {
    local code=$?
    err_echo "脚本异常退出 (code=$code)。已为你打开日志：$LOG_FILE"
    log "ERROR: exit_code=$code"
    /usr/bin/open "$LOG_FILE" >/dev/null 2>&1 || true
    exit $code
  }
  trap on_error ERR
  # ================================== 自述 ==================================
  show_intro() {
    cat <<'EOF' | jobs_intro_style auto
  📦==================================================
                  iOS IPA 打包助手
  ==================================================
  • 多 Target：用 fzf 选择工程和 Scheme（优先 B 系列）；Scheme 按 ← 返回工程
  • Enter 确认，Esc / Ctrl+C 取消；缺少 fzf 时停止，不自动采用第一项
  • 优先从 Build Settings 精确定位 .app；失败则自动从 DerivedData 回退匹配
  • 组装并导出为 .ipa 到指定目录（默认桌面）
  • 支持交互确认模式（--confirm）
  ==================================================
EOF
  }
  # ================================== 参数解析 ==================================
  parse_args() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --config)  CONFIG="${2:-Debug}"; shift 2 ;;
        --out)     OUT_DIR="${2:-$OUT_DIR}"; shift 2 ;;
        --project) PROJECT_PATH="${2:-}"; shift 2 ;;
        --scheme)  SCHEME="${2:-}"; shift 2 ;;
        --target)  TARGET="${2:-}"; shift 2 ;;
        --confirm) CONFIRM="1"; shift ;;
        -h|--help) exit 0 ;;
        *) shift ;;
      esac
    done
  }
  # 封装 prepare 对应的独立处理逻辑。
  prepare() {
    : > "$LOG_FILE"
    log "LOG_FILE=$LOG_FILE"
    log "PATH=$PATH"
    log "CONFIG=$CONFIG"
    log "OUT_DIR=$OUT_DIR"
    log "PROJECT_PATH=$PROJECT_PATH"
    log "SCHEME=$SCHEME"
    log "TARGET=$TARGET"
  }
  # ================================== repo root ==================================
  get_script_dir() {
    local script_path="${(%):-%x}"
    [[ -n "$script_path" ]] || script_path="$0"
    if [[ "$script_path" != /* ]]; then
      script_path="$(cd "$(dirname "$script_path")" && /bin/pwd)/$(basename "$script_path")"
    fi
    echo "$(cd "$(dirname "$script_path")" && /bin/pwd)"
  }
  # 解析并返回后续流程需要的目标信息。
  find_repo_root() {
    local script_dir root
    script_dir="$(get_script_dir)"
    if /usr/bin/command -v git >/dev/null 2>&1; then
      root="$(cd "$script_dir" && /usr/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
      [[ -n "$root" ]] && { echo "$root"; return; }
    fi
    echo "$script_dir"
  }
  # ================================== fzf ==================================
  has_fzf() {
    [[ -n "$IPA_FZF_BIN" && -x "$IPA_FZF_BIN" ]] || return 1
    FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$IPA_FZF_BIN" --version >/dev/null 2>&1
  }
  # 选择单项，使用独立返回码区分上一层、取消与选择器失败。
  fzf_pick_one() {
    local prompt="$1" back_title="${2:-}" initial_value="${3:-}" result="" result_code=0 hint='↑↓ 或输入搜索；Enter 确认；Esc / Ctrl+C 取消' key="" rows="" row="" help_text="" position=0
    local -a options=(--sync --no-multi --no-sort --height=~60% --layout=reverse --border --prompt="$prompt") candidates=()
    if ! has_fzf; then
      err_echo 'fzf 缺失或不可用；请先运行 brew install fzf，没有选择目标或生成 IPA。' >&2
      return 2
    fi
    help_text="$(FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$IPA_FZF_BIN" --help)" || return 2
    [[ "$help_text" == *--footer* ]] || { err_echo 'fzf 版本过旧，请更新后重试。' >&2; return 2; }
    rows="$(/bin/cat)"
    [[ -n "$rows" ]] || return 1
    candidates=("${(@f)rows}")
    if [[ -n "$back_title" ]]; then
      hint+=$'\n'"← 返回$back_title"
      options+=(--expect=left)
    fi
    for row in "${candidates[@]}"; do
      (( position++ ))
      [[ -n "$initial_value" && "$row" == "$initial_value" ]] && options+=(--bind="start:pos($position)")
    done
    options+=(--header="$hint" --footer="$hint")
    result="$(printf '%s\n' "${candidates[@]}" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= FZF_DEFAULT_COMMAND= "$IPA_FZF_BIN" "${options[@]}")" || result_code=$?
    if [[ -n "$back_title" && "${result%%$'\n'*}" == left && ( "$result_code" == 0 || "$result_code" == 1 ) ]]; then
      return 10
    fi
    case "$result_code" in
      0) ;;
      1|130) return 1 ;;
      *) err_echo "fzf 选择失败（退出码 $result_code），没有生成 IPA。" >&2; return 2 ;;
    esac
    if [[ -n "$back_title" ]]; then
      key="${result%%$'\n'*}"
      [[ "$result" == *$'\n'* ]] || return 1
      result="${result#*$'\n'}"
    fi
    [[ -n "$result" ]] || return 1
    (( ${candidates[(Ie)$result]} > 0 )) || { err_echo 'fzf 返回了清单之外的目标。' >&2; return 2; }
    print -r -- "$result"
  }
  # ================================== choose project/workspace ==================================
  choose_project_path() {
    local root="$1"

    if [[ -n "$PROJECT_PATH" ]]; then
      [[ -e "$PROJECT_PATH" ]] || { err_echo "--project 指定路径不存在：$PROJECT_PATH" >&2; return 2; }
      echo "$PROJECT_PATH"; return 0
    fi

    local ws_list pj_list picked result_code=0
    ws_list="$(/usr/bin/find "$root" -maxdepth 12 -name "*.xcworkspace" -print 2>/dev/null | /usr/bin/awk '!/\.xcodeproj\/project\.xcworkspace$/')"
    pj_list="$(/usr/bin/find "$root" -maxdepth 12 -name "*.xcodeproj" -print 2>/dev/null)"
    [[ -n "$ws_list" || -n "$pj_list" ]] || { err_echo '未找到可用的 .xcworkspace / .xcodeproj。' >&2; return 2; }

    if [[ -n "$ws_list" ]]; then
      picked="$(printf "%s\n" "$ws_list" | /usr/bin/awk '{print length($0) "\t" $0}' | /usr/bin/sort -n | /usr/bin/cut -f2- \
        | fzf_pick_one "选择 Workspace/Project > " '' "$IPA_LAST_PROJECT")" || result_code=$?
    else
      picked="$(printf "%s\n" "$pj_list" | /usr/bin/awk '{print length($0) "\t" $0}' | /usr/bin/sort -n | /usr/bin/cut -f2- \
        | fzf_pick_one "选择 Workspace/Project > " '' "$IPA_LAST_PROJECT")" || result_code=$?
    fi
    (( result_code == 0 )) || return "$result_code"
    [[ -n "$picked" && -e "$picked" ]] || { err_echo "未找到可用的 .xcworkspace / .xcodeproj" >&2; return 2; }
    echo "$picked"
  }
  # ================================== xcodebuild -list raw (logged) ==================================
  xcodebuild_list_raw() {
    local proj="$1"
    local out="" code=0
    if [[ "$proj" == *.xcworkspace ]]; then
      out="$(/usr/bin/xcodebuild -list -workspace "$proj" 2>&1)" || code=$?
    else
      out="$(/usr/bin/xcodebuild -list -project "$proj" 2>&1)" || code=$?
    fi
    log "XCODEBUILD_LIST_EXIT=$code"
    log "XCODEBUILD_LIST_OUTPUT_BEGIN"
    printf "%s\n" "$out" >> "$LOG_FILE"
    log "XCODEBUILD_LIST_OUTPUT_END"
    [[ $code -eq 0 ]] || return 1
    printf "%s\n" "$out"
  }
  # 封装 list_schemes_text 对应的独立处理逻辑。
  list_schemes_text() {
    local proj="$1" out
    out="$(xcodebuild_list_raw "$proj" || true)"
    [[ -n "$out" ]] || return 1
    printf "%s\n" "$out" | /usr/bin/awk '
      # 封装 BEGIN 对应的独立处理逻辑。
      BEGIN{in_s=0}
      /^[[:space:]]*Schemes:/{in_s=1; next}
      in_s==1 {
        if ($0 ~ /^[[:space:]]*$/) next
        if ($0 ~ /^[^[:space:]]/) exit
        gsub(/^[[:space:]]+/, "", $0)
        print $0
      }
    '
  }
  # 封装 filter_main_schemes 对应的独立处理逻辑。
  filter_main_schemes() { /usr/bin/awk '/^B($|_)/{print}'; }
  # 收集并校验用户输入，决定后续执行路径。
  choose_scheme() {
    local proj="$1"
    [[ -n "$SCHEME" ]] && { echo "$SCHEME"; return 0; }

    local all schemes scount back_title=""
    all="$(list_schemes_text "$proj" || true)"
    schemes="$(printf "%s\n" "$all" | filter_main_schemes || true)"
    scount="$(printf "%s\n" "$schemes" | /usr/bin/awk 'NF{c++} END{print c+0}')"

    if [[ "$scount" -eq 0 ]]; then
      schemes="$all"
      scount="$(printf "%s\n" "$schemes" | /usr/bin/awk 'NF{c++} END{print c+0}')"
    fi

    [[ "$scount" -gt 0 ]] || { err_echo "未获取到任何 Scheme（看日志 $LOG_FILE）" >&2; return 2; }
    [[ -z "$PROJECT_PATH" ]] && back_title='Workspace/Project'
    printf "%s\n" "$schemes" | fzf_pick_one "选择要打包的 Scheme（优先 B 系列）> " "$back_title"
  }
  # 在工程与 Scheme 面板间往返，全部确认后才交给 IPA 封装流程。
  choose_packaging_target() {
    local root="$1" proj="" scheme="" result_code=0
    while true; do
      result_code=0
      proj="$(choose_project_path "$root")" || result_code=$?
      (( result_code == 0 )) || return "$result_code"
      IPA_LAST_PROJECT="$proj"
      result_code=0
      scheme="$(choose_scheme "$proj")" || result_code=$?
      (( result_code == 10 )) && continue
      (( result_code == 0 )) || return "$result_code"
      IPA_SELECTED_PROJECT="$proj"
      IPA_SELECTED_SCHEME="$scheme"
      return 0
    done
  }
  # 封装 maybe_confirm 对应的独立处理逻辑。
  maybe_confirm() {
    local proj="$1" scheme="$2"
    if [[ "$CONFIRM" == "1" ]]; then
      echo ""
      info_echo "📁 工程：$(basename "$proj")"
      info_echo "🎯 Scheme：$scheme"
      info_echo "🔧 配置：$CONFIG"
      info_echo "📦 输出：$OUT_DIR"
      read -r "?👉 按回车继续，Ctrl+C 取消..."
    fi
  }
  # ================================== DerivedData fallback ==================================
  get_derived_data_dir() {
    local custom
    custom="$(/usr/bin/defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation 2>/dev/null || true)"
    if [[ -n "$custom" && -d "$custom" ]]; then
      echo "$custom"
    else
      echo "${HOME}/Library/Developer/Xcode/DerivedData"
    fi
  }
  # 解析并返回后续流程需要的目标信息。
  find_app_in_derived_data() {
    local scheme="$1"
    local derived
    derived="$(get_derived_data_dir)"
    log "DERIVED_DATA_DIR=$derived"
    [[ -d "$derived" ]] || return 1

    local best="" best_m=0 hit=0

    while IFS= read -r -d '' app; do
      hit=$((hit+1))
      local m; m="$(/usr/bin/stat -f '%m' "$app" 2>/dev/null || echo 0)"
      if [[ "$m" -gt "$best_m" ]]; then best_m="$m"; best="$app"; fi
    done < <(/usr/bin/find "$derived" -type d -path "*/Build/Products/*-iphoneos/${scheme}.app" -print0 2>/dev/null)

    log "DERIVED_MATCH_COUNT(same_name)=$hit best_mtime=$best_m best=$best"
    if [[ -n "$best" && -d "$best" ]]; then
      echo "$best"
      return 0
    fi

    best=""; best_m=0; hit=0
    while IFS= read -r -d '' app; do
      hit=$((hit+1))
      local m; m="$(/usr/bin/stat -f '%m' "$app" 2>/dev/null || echo 0)"
      if [[ "$m" -gt "$best_m" ]]; then best_m="$m"; best="$app"; fi
    done < <(/usr/bin/find "$derived" -type d -path "*/Build/Products/*-iphoneos/*.app" -print0 2>/dev/null)

    log "DERIVED_MATCH_COUNT(any)=$hit best_mtime=$best_m best=$best"
    [[ -n "$best" && -d "$best" ]] || return 1
    echo "$best"
  }
  # ================================== 关键：showBuildSettings（稳抓 .app） ==================================
  get_app_path() {
    local proj="$1" scheme="$2"

    local cmd=()
    if [[ "$proj" == *.xcworkspace ]]; then
      cmd=(/usr/bin/xcodebuild -workspace "$proj" -scheme "$scheme" -configuration "$CONFIG" -sdk iphoneos -showBuildSettings)
    else
      cmd=(/usr/bin/xcodebuild -project "$proj" -scheme "$scheme" -configuration "$CONFIG" -sdk iphoneos -showBuildSettings)
    fi

    local out="" code=0
    out="$("${cmd[@]}" 2>&1)" || code=$?

    log "XCODEBUILD_SHOWBUILDSETTINGS_EXIT=$code"
    log "XCODEBUILD_SHOWBUILDSETTINGS_OUTPUT_BEGIN"
    printf "%s\n" "$out" >> "$LOG_FILE"
    log "XCODEBUILD_SHOWBUILDSETTINGS_OUTPUT_END"

    if [[ $code -eq 0 ]]; then
      # 1) 最稳：CODESIGNING_FOLDER_PATH 直接就是 *.app
      local codesign_path
      codesign_path="$(printf "%s\n" "$out" | /usr/bin/awk -F'=' '
        function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/,"",s);return s}
        {
          k=trim($1); v=trim($2)
          if (k=="CODESIGNING_FOLDER_PATH") { print v; exit }
        }')"
      if [[ -n "$codesign_path" ]]; then
        echo "$codesign_path"
        return 0
      fi

      # 2) 备用：TARGET_BUILD_DIR + WRAPPER_NAME
      local target_build_dir wrapper_name
      target_build_dir="$(printf "%s\n" "$out" | /usr/bin/awk -F'=' '
        function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/,"",s);return s}
        {k=trim($1); v=trim($2); if (k=="TARGET_BUILD_DIR"){print v; exit}}')"
      wrapper_name="$(printf "%s\n" "$out" | /usr/bin/awk -F'=' '
        function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/,"",s);return s}
        {k=trim($1); v=trim($2); if (k=="WRAPPER_NAME"){print v; exit}}')"
      if [[ -n "$target_build_dir" && -n "$wrapper_name" ]]; then
        echo "${target_build_dir}/${wrapper_name}"
        return 0
      fi
    fi

    warn_echo "⚠️  Build Settings 未解析到 .app，改用 DerivedData 回退匹配 ${scheme}.app"
    log "FALLBACK_TO_DERIVEDDATA scheme=$scheme"
    find_app_in_derived_data "$scheme"
  }
  # ================================== ipa name + package ==================================
  infer_ipa_name() {
    local app_dir="$1" fallback="$2"
    local plist="$app_dir/Info.plist" name=""
    if [[ -f "$plist" ]]; then
      name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null || true)
      [[ -z "$name" ]] && name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null || true)
    fi
    [[ -n "$name" ]] || name="$fallback"
    echo "$name"
  }
  # 封装 package_ipa 对应的独立处理逻辑。
  package_ipa() {
    local app_dir="$1" ipa_path="$2"
    local tmp_dir payload_dir
    tmp_dir="$(/usr/bin/mktemp -d)"
    payload_dir="${tmp_dir}/Payload"
    /bin/mkdir -p "$payload_dir"
    /bin/cp -R "$app_dir" "$payload_dir/"
    info_echo "📦 正在打包为 .ipa ..."
    log "ZIP_START tmp_dir=$tmp_dir ipa=$ipa_path app=$app_dir"
    ( cd "$tmp_dir" && /usr/bin/zip -qry "$ipa_path" "Payload" )
    /bin/rm -rf "$tmp_dir"
    log "ZIP_DONE ipa=$ipa_path"
  }
  # ================================== main ==================================
  main() {
    show_intro
    parse_args "$@"
    prepare

    local repo_root proj scheme app_path ipa_name ipa_path selection_code=0

    repo_root="$(find_repo_root)"
    info_echo "📂 工作目录：$repo_root"
    log "repo_root=$repo_root"
    log "PWD=$PWD  0=$0  x=${(%):-%x}"

    choose_packaging_target "$repo_root" || selection_code=$?
    if (( selection_code == 1 )); then
      info_echo '已取消目标选择，没有生成 IPA。'
      return 0
    elif (( selection_code != 0 )); then
      return "$selection_code"
    fi
    proj="$IPA_SELECTED_PROJECT"
    scheme="$IPA_SELECTED_SCHEME"
    success_echo "发现工程：$(basename "$proj")"
    log "project=$proj"

    success_echo "选择 scheme：$scheme"
    log "scheme=$scheme"

    maybe_confirm "$proj" "$scheme"

    app_path="$(get_app_path "$proj" "$scheme" || true)"
    [[ -n "$app_path" && -d "$app_path" ]] || { err_echo "未能定位 .app（看日志：$LOG_FILE）"; exit 1; }

    success_echo "已定位 .app：$app_path"
    log "app_path=$app_path"

    ipa_name="$(infer_ipa_name "$app_path" "$scheme")"
    ipa_path="${OUT_DIR}/${ipa_name}.ipa"

    /bin/mkdir -p "$OUT_DIR"
    package_ipa "$app_path" "$ipa_path"
    success_echo "🎉 打包完成：$ipa_path"
    info_echo "🧾 日志：$LOG_FILE"
    log "ipa=$ipa_path"

    /usr/bin/open -R "$ipa_path" 2>/dev/null || true
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
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
