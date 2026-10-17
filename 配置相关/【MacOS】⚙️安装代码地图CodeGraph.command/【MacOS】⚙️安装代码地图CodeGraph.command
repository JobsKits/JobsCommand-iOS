#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️安装代码地图CodeGraph.command
# - 核心用途：逐层体检系统工具、Homebrew、Node、npm，安装或更新官方 CodeGraph CLI。
# - 影响范围：按确认安装工具；仅维护用户 CodeGraph 前缀及带标记的 shellenv 块，不给业务仓库建图。
# - 运行提示：先显示内置自述并回车确认；每个可选升级回车跳过，依赖失败立即停止。
# shell: zsh

SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
JOBS_HOMEBREW_BIN=""
JOBS_HOMEBREW_PREFIX=""
NODE_PREFIX=""
NODE_BIN=""
NPM_BIN=""
CODEGRAPH_PREFIX=""
CODEGRAPH_BIN=""
SAMPLE_DIR=""
CODEGRAPH_PACKAGE="@colbymchenry/codegraph"
NPM_REGISTRY="https://registry.npmjs.org/"
# 输出支持纯文本降级的脚本说明。
intro_line() {
  local role="$1" message="$2" color=34
  [[ "$role" != title ]] || color="1;31"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  else
    print -r -- "$message"
  fi
}
# 在任何写入前说明用途、影响与取消方式。
show_script_intro_and_wait() {
  intro_line title "【MacOS】⚙️安装代码地图 CodeGraph"
  intro_line body "1、完整体检：系统工具 / CLT → Homebrew → Node.js → npm / registry → CodeGraph。"
  intro_line body "2、健康 Node/npm 直接复用；缺失时用 Homebrew node@24。官方包使用用户独立前缀。"
  intro_line body "3、每层安装或修复后复检，失败立即停止；Homebrew doctor 不通过时不继续安装。"
  intro_line body "4、不会为业务仓库初始化 .codegraph，也不会调用 codegraph install 修改 AI 配置。"
  intro_line body "5、日志在系统临时目录的「【MacOS】⚙️安装代码地图CodeGraph.log」。按 Ctrl+C 取消。"
  if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    intro_line body "用法：/bin/zsh ./【MacOS】⚙️安装代码地图CodeGraph.command"
    exit 0
  fi
  if (( $# != 0 )); then
    print -u2 -r -- "✖ 不支持的参数；使用 --help 查看说明。"
    exit 2
  fi
  [[ -t 0 ]] || { print -u2 -r -- "✖ 请在可交互终端运行，尚未安装或写入配置。"; exit 1; }
  IFS= read -r "?已了解用途与影响，按回车继续；Ctrl+C 取消：" _ || exit 1
}
# 确认后初始化路径、日志和当前会话选项。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  SCRIPT_PATH="${${(%):-%x}:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  CODEGRAPH_PREFIX="$HOME/.local/share/jobs-codegraph"
  : > "$LOG_FILE" || exit 1
  trap 'cleanup_sample; exit 130' INT
  trap 'cleanup_sample; exit 143' TERM
}
# 将分级日志同步到终端和日志文件。
log_message() {
  local level="$1" message="$2" color=34
  case "$level" in
    OK) color=32 ;;
    WARN) color=33 ;;
    ERROR) color=31 ;;
  esac
  print -r -- "[$level] $message" >> "$LOG_FILE"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[1;%sm[%s] %s\033[0m\n' "$color" "$level" "$message"
  else
    print -r -- "[$level] $message"
  fi
}
# 保留外部命令原始退出码并记录完整诊断。
run_logged() {
  "$@" 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local result=${pipestatus[1]}
  if (( result != 0 )); then
    log_message ERROR "命令失败（$result）：${(j: :)${(q)@}}"
  fi
  return "$result"
}
# 可选安装或更新必须主动输入；回车表示不执行。
ask_to_run() {
  local answer=""
  IFS= read -r "?$1（直接回车跳过；输入任意字符后回车执行）：" answer || return 1
  [[ -n "$answer" ]]
}
# 必需动作被跳过时停止整条依赖链。
require_action() {
  ask_to_run "$1" && return 0
  log_message ERROR "必需步骤已取消，停止安装。"
  return 1
}
# 检查安装路径真实依赖的系统命令和开发工具，不借检查隐式安装。
check_system_toolchain() {
  local tool compiler=""
  [[ "$(uname -s)" == Darwin ]] || { log_message ERROR "仅支持 macOS / zsh。"; exit 1; }
  (( EUID != 0 )) || { log_message ERROR "请以当前普通用户运行，不使用 sudo 启动本脚本。"; exit 1; }
  for tool in /bin/bash /usr/bin/curl /usr/bin/git /usr/bin/xcode-select /usr/bin/xcrun /usr/bin/make; do
    [[ -x "$tool" ]] || { log_message ERROR "缺少基础工具：$tool"; exit 1; }
  done
  run_logged /bin/bash --version || exit 1
  run_logged /usr/bin/curl --version || exit 1
  if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
    if ask_to_run "缺少 Command Line Tools，打开系统安装窗口"; then
      run_logged /usr/bin/xcode-select --install
    fi
    log_message ERROR "请完成 Command Line Tools 安装后重新运行；下游尚未执行。"
    exit 1
  fi
  run_logged /usr/bin/git --version || exit 1
  compiler="$(/usr/bin/xcrun --find clang 2>>"$LOG_FILE")" || {
    log_message ERROR "CLT / Xcode 开发目录失效；请检查 xcode-select -p 与 Xcode 许可。"
    exit 1
  }
  run_logged "$compiler" --version || exit 1
  run_logged /usr/bin/make --version || exit 1
  log_message OK "系统工具与 CLT 可执行。"
}
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  log_message INFO "$*" >&2
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
  if run_logged curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    run_logged /bin/bash "$installer" || installer_result=$?
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
  if ! run_logged curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! run_logged env GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! run_logged "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! run_logged "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
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
# 完整体检 Homebrew；doctor 诊断不能被成功提示吞掉。
check_homebrew_health() {
  run_logged "$JOBS_HOMEBREW_BIN" --version || return 1
  JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix 2>>"$LOG_FILE")" || return 1
  [[ "$JOBS_HOMEBREW_PREFIX" == /* && -d "$JOBS_HOMEBREW_PREFIX" ]] || return 1
  run_logged "$JOBS_HOMEBREW_BIN" config || return 1
  if ! run_logged "$JOBS_HOMEBREW_BIN" doctor; then
    log_message ERROR "Homebrew doctor 未通过，请按日志处理后重跑；未继续安装下游依赖。"
    return 1
  fi
  log_message OK "Homebrew 健康体检通过：$JOBS_HOMEBREW_BIN"
}
# 检查或安装 Homebrew，在通过体检后才允许可选更新。
ensure_homebrew() {
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  jobs_brew_install_or_exit
  check_homebrew_health || exit 1
  if ask_to_run "更新 Homebrew 自身与公式元数据（不全员升级或清理）"; then
    run_logged "$JOBS_HOMEBREW_BIN" update || exit 1
    check_homebrew_health || exit 1
  fi
}
# 通过实际 JS 执行验证 Node，并验证该环境配套的 npm。
check_node_npm_health() {
  [[ -x "$NODE_BIN" && -x "$NPM_BIN" ]] || return 1
  run_logged "$NODE_BIN" --version || return 1
  run_logged "$NODE_BIN" -e 'if (Number(process.versions.node.split(".")[0]) < 20) process.exit(1); console.log("Node JS 执行与内置模块：", require("node:os").platform(), require("node:path").basename("/node/ok"));' || return 1
  run_logged "$NPM_BIN" --version || return 1
  "$NPM_BIN" config get prefix >>"$LOG_FILE" 2>&1 || return 1
  "$NPM_BIN" root --global >>"$LOG_FILE" 2>&1 || return 1
}
# 刷新 Brew 管理的 Node/npm，避免 PATH 里的旧 shim 抢占运行时。
activate_node_npm() {
  NODE_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix node@24 2>>"$LOG_FILE")" || return 1
  [[ "$NODE_PREFIX" == /* && -d "$NODE_PREFIX" ]] || return 1
  NODE_BIN="$NODE_PREFIX/bin/node"
  NPM_BIN="$NODE_PREFIX/bin/npm"
  export PATH="$NODE_PREFIX/bin:$PATH"
  rehash
}
# 从当前会话和 Brew 前缀发现成套 Node/npm，复用健康的等价运行环境。
find_healthy_node_npm() {
  local candidate="" node_path="$(command -v node 2>/dev/null)" formula="" prefix=""
  local -a candidates
  [[ "$node_path" == /* ]] && candidates+=("${node_path:h}")
  for formula in node@24 node node@22; do
    prefix="$("$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>>"$LOG_FILE")" || continue
    [[ "$prefix" == /* ]] && candidates+=("$prefix/bin")
  done
  for candidate in "${candidates[@]}"; do
    NODE_PREFIX="${candidate:h}"
    NODE_BIN="$candidate/node"
    NPM_BIN="$candidate/npm"
    export PATH="$candidate:$PATH"
    rehash
    if check_node_npm_health; then
      return 0
    fi
  done
  return 1
}
# 仅针对缺失或损坏的 Node/npm 修复一次，健康环境可选升级。
ensure_node_npm() {
  local formula_present=0
  "$JOBS_HOMEBREW_BIN" list --versions node@24 >>"$LOG_FILE" 2>&1 && formula_present=1
  if find_healthy_node_npm; then
    log_message OK "复用健康 Node/npm：$NODE_BIN / $NPM_BIN"
    return 0
  else
    if (( formula_present )); then
      require_action "Node/npm 健康检查失败，重新安装 Homebrew node@24" || exit 1
      run_logged "$JOBS_HOMEBREW_BIN" reinstall node@24 || exit 1
    else
      require_action "安装必需基础组件 Homebrew node@24（包含 npm）" || exit 1
      run_logged "$JOBS_HOMEBREW_BIN" install node@24 || exit 1
    fi
  fi
  activate_node_npm && check_node_npm_health || {
    log_message ERROR "Node/npm 安装后复检失败，停止，不反复重装；请检查日志、CLT 与 Brew 前缀。"
    exit 1
  }
  log_message OK "Node 与 npm 分别通过本地可执行性检查。"
}
# 检查 npm 的实际下载通道，失败不进入 CodeGraph 安装。
check_npm_registry() {
  run_logged "$NPM_BIN" ping --registry "$NPM_REGISTRY" --fetch-retries=1 --fetch-timeout=30000 || {
    log_message ERROR "npm 官方 registry 不可用；检查网络或现有代理后重跑，不关闭 TLS 校验。"
    exit 1
  }
  log_message OK "npm registry 网络体检通过。"
}
# 只复用可识别为官方 scoped npm 包的健康安装。
codegraph_candidate_ok() {
  local candidate="$1"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  "$NODE_BIN" - "$candidate" "$CODEGRAPH_PACKAGE" <<'NODE' >>"$LOG_FILE" 2>&1 || return 1
const fs = require("node:fs"), path = require("node:path");
let directory = path.dirname(fs.realpathSync(process.argv[2]));
for (;;) {
  const manifest = path.join(directory, "package.json");
  if (fs.existsSync(manifest) && JSON.parse(fs.readFileSync(manifest, "utf8")).name === process.argv[3]) process.exit(0);
  const parent = path.dirname(directory);
  if (parent === directory) process.exit(1);
  directory = parent;
}
NODE
  CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" --version >>"$LOG_FILE" 2>&1 || return 1
  CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" init --help >>"$LOG_FILE" 2>&1 || return 1
  CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$candidate" index --help >>"$LOG_FILE" 2>&1 || return 1
}
# 依次发现用户专属安装和已有全局安装，不按前缀可写性重复安装。
find_codegraph() {
  local candidate
  local -a candidates
  candidates=("$CODEGRAPH_PREFIX/bin/codegraph" "$(command -v codegraph 2>/dev/null)"
    "$JOBS_HOMEBREW_PREFIX/bin/codegraph" /opt/homebrew/bin/codegraph /usr/local/bin/codegraph)
  for candidate in "${candidates[@]}"; do
    if codegraph_candidate_ok "$candidate"; then
      CODEGRAPH_BIN="$candidate"
      return 0
    fi
  done
  return 1
}
# 使用独立 npm 前缀安装，保留平台二进制可选依赖且不使用 sudo。
install_official_codegraph() {
  [[ ! -L "$CODEGRAPH_PREFIX" ]] || {
    log_message ERROR "受控 npm 前缀是符号链接，停止以免写入未知目标：$CODEGRAPH_PREFIX"
    return 1
  }
  run_logged "$NPM_BIN" install --global --prefix "$CODEGRAPH_PREFIX" --registry "$NPM_REGISTRY" \
    --include=optional --engine-strict --fetch-retries=1 --fetch-timeout=60000 "$CODEGRAPH_PACKAGE@latest" || return 1
  CODEGRAPH_BIN="$CODEGRAPH_PREFIX/bin/codegraph"
  codegraph_candidate_ok "$CODEGRAPH_BIN" || {
    log_message ERROR "官方包安装后仍不能运行，请检查 npm 平台可选包；不自动隐藏错误或改用同名包。"
    return 1
  }
}
# 健康安装复用，主动选择更新时写入受控前缀。
ensure_codegraph() {
  if find_codegraph; then
    log_message OK "发现健康的官方 CodeGraph：$CODEGRAPH_BIN"
    if ask_to_run "安装或更新官方 CodeGraph 到用户独立前缀（保留原全局安装）"; then
      install_official_codegraph || exit 1
    fi
  else
    require_action "安装必需的官方 CodeGraph CLI" || exit 1
    install_official_codegraph || exit 1
  fi
}
# 只清理本次创建的已知临时样例，异常退出也执行。
cleanup_sample() {
  if [[ -n "$SAMPLE_DIR" && "$SAMPLE_DIR" == /private/tmp/jobs-codegraph-check.* && -d "$SAMPLE_DIR" ]]; then
    /bin/rm -r -- "$SAMPLE_DIR" || return 1
  fi
  SAMPLE_DIR=""
}
# 使用本机临时样例验证建图内核，禁用遥测、自动下载和后台扩展。
verify_codegraph_engine() {
  local sample_dir="" result=0 report=""
  sample_dir="$(mktemp -d /private/tmp/jobs-codegraph-check.XXXXXX)" || exit 1
  SAMPLE_DIR="$sample_dir"
  trap cleanup_sample EXIT
  print -r -- 'export function codegraphHealthCheck(value) { return value + 1; }' > "$sample_dir/health.js" || result=1
  if (( result == 0 )); then
    run_logged env CODEGRAPH_NO_WATCH=1 CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 \
      NODE_DISABLE_COMPILE_CACHE=1 CODEGRAPH_NO_DOWNLOAD=1 "$CODEGRAPH_BIN" init --yes "$sample_dir" || result=1
  fi
  if (( result == 0 )); then
    report="$(env CODEGRAPH_NO_WATCH=1 CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 \
      NODE_DISABLE_COMPILE_CACHE=1 CODEGRAPH_NO_DOWNLOAD=1 "$CODEGRAPH_BIN" status --json "$sample_dir" 2>>"$LOG_FILE")" || result=1
    print -r -- "$report" >> "$LOG_FILE"
    if (( result == 0 )); then
      print -r -- "$report" | "$NODE_BIN" -e '
const fs = require("node:fs");
try {
  const s = JSON.parse(fs.readFileSync(0, "utf8"));
  const expected = fs.realpathSync(process.argv[1]);
  if (s.initialized !== true || fs.realpathSync(s.projectPath) !== expected || !s.lastIndexed ||
      s.index?.state !== "complete" || !(s.fileCount > 0) || !(s.nodeCount > 0)) process.exit(1);
} catch { process.exit(1); }' "$sample_dir" || result=1
    fi
  fi
  cleanup_sample || result=1
  if (( result != 0 )); then
    log_message ERROR "CodeGraph 真实建图复检失败（不只检查版本号），请查看日志。"
    exit 1
  fi
  log_message OK "CodeGraph 临时样例建图、数据库与完整状态复检通过。"
}
# 幂等写入专属 PATH 块，保留配置原有内容及符号链接。
save_codegraph_environment() {
  local profile_file="$HOME/.zprofile" profile_stage=""
  local begin='# >>> Jobs CodeGraph environment >>>' end='# <<< Jobs CodeGraph environment <<<' environment_path=""
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-codegraph-profile.XXXXXX")" || exit 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { if (inside) exit 2; inside = 1; next }
      $0 == end { if (!inside) exit 2; inside = 0; next }
      !inside { print }
      END { if (inside) exit 2 }
    ' "$profile_file" > "$profile_stage" || { /bin/rm -- "$profile_stage"; exit 1; }
  fi
  {
    print -r -- "$begin"
    environment_path="$NODE_PREFIX/bin:${CODEGRAPH_BIN:h}"
    print -r -- "export PATH=${(q)environment_path}:\"\$PATH\""
    print -r -- "$end"
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    if [[ -e "$profile_file" ]]; then
      cp -p "$profile_file" "$profile_file.jobs-codegraph.$(date +%Y%m%d-%H%M%S).$$.bak" || exit 1
    fi
    cat "$profile_stage" > "$profile_file" || exit 1
  fi
  /bin/rm -- "$profile_stage"
  export PATH="$NODE_PREFIX/bin:${CODEGRAPH_BIN:h}:$PATH"
  rehash
}
# 汇报最终安装与使用入口，不把 CLI 安装等同项目建图。
show_result() {
  run_logged env CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$CODEGRAPH_BIN" --version || exit 1
  log_message OK "CodeGraph CLI 已就绪：$CODEGRAPH_BIN"
  log_message INFO "新开终端后使用 codemap 或 codemap「手动输入 / 拖入路径」构建代码地图。"
  log_message INFO "日志：$LOG_FILE"
}
# 编排确认、完整依赖链体检、安装与实际建图复检。
main() {
  show_script_intro_and_wait "$@" # 先解释用途与影响，确认前不写日志或安装。
  initialize_runtime # 初始化当前会话选项、可迁移路径和日志。
  check_system_toolchain # 先检查 Homebrew 安装与运行依赖的系统基础工具。
  ensure_homebrew # 发现或安装 Homebrew 并通过 config / doctor 体检。
  ensure_node_npm # 单独验证 Node 执行 JS 与 npm，必要时定点安装修复。
  check_npm_registry # 验证 npm 实际下载通道，失败立即停止。
  ensure_codegraph # 复用健康官方安装，按确认安装或更新独立前缀。
  verify_codegraph_engine # 用隔离样例验证实际建图与数据库完整状态。
  save_codegraph_environment # 验证完成后注册用户 PATH，并刷新当前会话。
  show_result # 输出可用版本、命令路径和日志。
}

main "$@"

