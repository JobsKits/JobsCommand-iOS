#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️发布Cocoapods组件.command
# - 核心用途：执行“⚙️发布Cocoapods组件”对应的移动端项目自动化任务。
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
  print -r -- '脚本名称：【MacOS】⚙️发布Cocoapods组件.command' | jobs_intro_style title
  print -r -- '核心用途：执行“⚙️发布Cocoapods组件”对应的移动端项目自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  echo "温馨提示：手动编辑 *.podspec 以后，再使用本工具。"
  # 默认邮箱（用户名）、Token（密码）
  default_email="295060456@qq.com"
  default_token="YOUR_TOKEN"
  # 声明全局变量 declare
  declare -g current_directory="" # 当前文件夹路径
  declare -ag podspec_files=() # 【数组】同一个文件夹下，可能有多个*.podspec文件
  declare -g current_podspec="" # 当前*.podspec文件相对路径
  declare -g current_podspec2="" # 当前*.podspec文件绝对路径
  declare -g current_version=""  # 当前*.podspec文件里面的版本号
  declare -g major="" # 主版本号
  declare -g minor="" # 次版本号
  declare -g patch="" # 补丁版本号
  declare -g next_version="" # 最新的版本号
  # 定位资源函数
  location() {
      # 获取当前文件夹路径
      current_directory=$(dirname "$(realpath "$0")")
      cd "$current_directory"  # 切换到当前目录
      echo -ne "\033[1m当前文件夹路径为：\033[0m"
      echo -e "\033[31m$current_directory\033[0m"

      # 获取当前文件夹内后缀名为podspec的文件名列表，并存储到数组中
      podspec_files=()
      while IFS= read -r -d '' file; do
          podspec_files+=("$file")
      done < <(find . -maxdepth 1 -type f -name "*.podspec" -print0)

      if [ ${#podspec_files[@]} -eq 0 ]; then
          echo "在当前文件夹中，没有找到*.podspec文件。请检查！！！"
          exit
      fi

      if [ ${#podspec_files[@]} -eq 1 ]; then
          echo "在当前文件夹中，只找到了1个 *.podspec 文件。将会自动使用这个文件."
          chosen_index=0
      else
          echo "在当前文件夹中找到了 ${#podspec_files[@]} 个 *.podspec 文件。请手动选择要使用的文件。"
          echo -e "\033[1m当前文件夹路径里面的\033[0m\033[30m*.podspec\033[0m\033[1m文件的列表：\033[0m"
          for ((i=0; i<${#podspec_files[@]}; i++)); do
              echo "$(($i+1)): ${podspec_files[$i]}"
          done
          echo -n "请选择要使用的 *.podspec 文件编号："
          read -r choice
          # 确保用户输入为数字且在合法范围内
          if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#podspec_files[@]} ]; then
              echo "无效的输入。请输入：数字1~ ${#podspec_files[@]}."
              exit
          fi
          chosen_index=$(($choice - 1))
      fi

      echo -ne "\033[1m已选择的 *.podspec 文件的相对路径为：\033[0m"
      echo -e "\033[31m${podspec_files[$chosen_index]}\033[0m"
      current_podspec=("${podspec_files[$chosen_index]}")
      echo -ne "\033[1m已选择的 *.podspec 文件的绝对路径为：\033[0m"
      echo -e "\033[31m$current_directory${podspec_files[$chosen_index]#.}\033[0m"
      current_podspec2=$current_directory${podspec_files[$chosen_index]#.}
  }
  # 获取当前版本号的函数(核心)
  get_current_version_core() {
      # 使用 grep 找到 Pod::Spec.new do |spec| 并提取其中的spec名称
      spec_name=$(grep -o 'Pod::Spec.new do |[^|]*|' "$current_podspec" | sed -e 's/Pod::Spec.new do |//' -e 's/|//') # spec
      # 输出带有${spec_name}.version整行的内容
      matched_line=$(grep "${spec_name}\.version\s*=" "$current_podspec")
      # 提取 matched_line 变量中的内容，该内容被单引号或双引号包裹
      current_version=$(echo "$matched_line" | grep -oE "'[^']+'|\"[^\"]+\"" | sed -e "s/'//g" -e 's/"//g')
  }
  # 获取当前版本号的函数
  get_current_version() {
      if [ -z "$current_podspec" ]; then
          echo "未选择 *.podspec 文件。"
          exit
      fi
      get_current_version_core
      # 输出提取到的版本号
      echo -ne "\033[1m当前版本号为：\033[0m"
      echo -e "\033[31m${current_version}\033[0m"
      echo
  }
  # 对*.podspec文件的版本号进行替换
  replace_version() {
      get_current_version_core
      # 替换 *.podspec 文件中的版本号字段为用户输入的下一个版本号
      # 在路径current_podspec下，将current_version替换成next_version
      sed -i.bak 's/'${current_version}'/'${next_version}'/g' "$current_podspec"
      # 删除生成的备份文件
      rm "${current_podspec}.bak"
  }
  # 内容输入过滤
  pause_or_exit() {
      echo "按回车键继续，或者输入任意字符+回车，则终止操作:"
      IFS= read -r response || exit 1
      if [ -z "$response" ]; then
          echo "继续操作..."
      else
          echo "终止操作"
          exit 0
      fi
  }
  # 获取版本号
  get_next_version() {
      # current_version=$(grep -E 's.version\s+=' "${1}" | cut -d '"' -f 2)
      # 将当前版本号按照点号进行分割，并提取第一个字段，即主版本号
      major=$(echo "${current_version}" | cut -d '.' -f 1)
      # 将当前版本号按照点号进行分割，并提取第二个字段，即次版本号
      minor=$(echo "${current_version}" | cut -d '.' -f 2)
      # 将当前版本号按照点号进行分割，并提取第三个字段，即补丁版本号
      patch=$(echo "${current_version}" | cut -d '.' -f 3)
  }
  # 提示用户选择定义版本号的方式
  prompt_version_selection() {
      echo "当前版本号：$current_version"
      echo "1. 主版本号递增：$((major+1)).${minor}.${patch}"
      echo "2. 次版本号递增：${major}.$((minor+1)).${patch}"
      echo "3. 补丁版本号递增：${major}.${minor}.$((patch+1))"
      echo "4. 自定义版本号。版本号格式为: x.x.x "
      read "?请选择版本号的递增方式（输入相应数字）: " selection
      case $selection in
          1) next_version="$((major+1)).${minor}.${patch}" ;;
          2) next_version="${major}.$((minor+1)).${patch}" ;;
          3) next_version="${major}.${minor}.$((patch+1))" ;;
          4) read "?请输入自定义版本号: " next_version ;;
          *) echo "无效的选择" && exit 1 ;;
      esac
    
      echo -ne "\033[1m当前版本号为：\033[0m"
      echo -e "\033[31m${current_version}\033[0m"

      echo -ne "\033[1m下一个版本号为：\033[0m"
      echo -e "\033[31m${next_version}\033[0m"
  }
  # 发布CocoaPods
  publish_cocoapods() {
      # 检查是否已注册成功。如果注册成功，是不需要点击邮箱验证
      if ! pod trunk me &> /dev/null; then
          # 输入邮箱（用户名）
          read "?Enter email (default: $default_email): " email
          email=${email:-$default_email}

          # 输入Token（密码）
          read "?Enter token (default: $default_token): " token
          token=${token:-$default_token}

          # 注册 CocoaPods Trunk
          pod trunk register "$email" "$token"
      else
          echo "已经注册 CocoaPods Trunk 。则跳过"
          # 执行pod spec lint命令，并在每个文件通过lint后推送到CocoaPods
          echo "Linting $podspec_file"
          if pod spec lint --allow-warnings --verbose "$podspec_file"; then
              echo "Pushing $podspec_file to CocoaPods"
              pod trunk push "$podspec_file" --allow-warnings
          else
              echo "Failed to lint $podspec_file. Skipping push to CocoaPods."
          fi

          # 添加本地提交代码操作
          echo -e "\n ------ 执行 git 本地提交代码操作 ------ \n"
          read "?Enter commit message (default: 基础的配置): " git_commit_des
          git_commit_des=${git_commit_des:-"基础的配置"}  # 设置默认提交描述信息
          echo "git add ."
          git add .
          echo "git status"
          git status
          echo "git commit -m ${git_commit_des}"
          git commit -m "${git_commit_des}"

          # 添加打标签tag，并推送到远端
          echo -e "\n ------ 执行 git 打标签tag，并推送到远端 ------ \n"
          if [ -n "$next_version" ]; then
              if git rev-parse "refs/tags/${next_version}" >/dev/null 2>&1; then
                  echo "Tag ${next_version} already exists. Cancelling tag push."
              else
                  echo "git tag ${next_version}"
                  git tag "${next_version}"
                  echo "git push origin master --tags"
                  git push origin master --tags
              fi
          fi
      fi
  }

  location # 打印目标资源路径并设置样式
  get_current_version  # 获取当前版本号的函数
  pause_or_exit # 按回车键继续，或者输入任意字符+回车，则终止操作
  get_next_version # 获取版本号
  prompt_version_selection  # 提示用户选择定义版本号的方式
  replace_version # 对*.podspec文件的版本号进行替换
  publish_cocoapods # 发布CocoaPods

  :<<'COMMENT'
  提交库成功以后，因为各个DNS节点的数据同步问题，可能不能马上搜索的到，也就是在 https://cocoapods.org/ 上可能无法立即搜索到已经发布成功的Pods库
COMMENT

  :<<'COMMENT'
  pod spec lint 和 pod lib lint 都是用于校验 CocoaPods 规范的命令，但它们的使用场景略有不同。

  pod spec lint：
  这个命令用于校验一个单独的 .podspec 文件的规范性，即一个 CocoaPods 组件的描述文件。
  pod spec lint 命令会验证 .podspec 文件的语法、依赖关系、作者信息等是否符合 CocoaPods 的规范。

  pod lib lint：
  这个命令也用于校验一个 CocoaPods 组件，但它会在本地模拟建立一个空项目，并将该组件集成到项目中，然后执行一系列的检查。
  pod lib lint 命令会检查组件是否可以正确地集成到一个项目中，包括编译、链接、资源文件等等。
  区别主要在于两者的检查范围和深度：

  pod spec lint 只是对 .podspec 文件本身进行静态分析，确保其符合规范。
  pod lib lint 则会更适合确保一个 CocoaPods 组件可以正确地被集成到项目中，以及在项目中的行为是否符合预期。

  所以，一般来说，pod spec lint 用于对单个 .podspec 文件的静态规范进行校验，
  而 pod lib lint 则更适合确保一个 CocoaPods 组件可以正确地被集
COMMENT

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_original_logic "$@" # 执行 run_original_logic 对应的核心业务步骤。
  success_echo "脚本执行结束。日志：$LOG_FILE" # 输出脚本执行结果、摘要和日志位置。
}

main "$@"
