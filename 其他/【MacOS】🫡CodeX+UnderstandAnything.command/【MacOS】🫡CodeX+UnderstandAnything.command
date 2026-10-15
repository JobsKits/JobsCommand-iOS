#!/bin/zsh
# ==============================================================================
# CodeX+UnderstandAnything.command
# 用途：体检 Codex 与 Understand Anything，为 Xcode/iOS 工程生成中文知识图谱。
# 边界：只在用户确认后安装或升级；不挂接 pod install，不自动分析工程。
# 风险：安装流程会下载官方安装脚本，/understand 会消耗 Codex/AI 额度。
# 日志：通过内置自述后，终端输出同步写入系统临时目录中的同名 .log 文件。
# ==============================================================================

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
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_ios_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

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
APP_NAME="CodeX + Understand Anything"
UA_REPO="$HOME/.understand-anything/repo"
UA_INSTALL_URL="https://raw.githubusercontent.com/Lum1104/Understand-Anything/main/install.sh"

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t}"
LOG_FILE="${TMPDIR%/}/${SCRIPT_BASENAME}.log"

PROJECT_ROOT=""
typeset -ga XCODE_ITEMS=()

# 在任何落盘或联网动作前说明用途、影响和取消方式，避免双击误触。
show_script_intro_and_wait() {
  print -r -- "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- "脚本名称：${SCRIPT_BASENAME}" | jobs_intro_style title
  print -r -- "核心用途：体检 Codex 与 Understand Anything，并为指定 Xcode/iOS 工程准备代码图谱命令。" | jobs_intro_style body
  print -r -- "默认行为：确认后准备 Homebrew Python；生成图谱或启动 Codex 等动作仍单独询问。" | jobs_intro_style body
  print -r -- "可能影响：用户确认后，可能下载官方安装脚本并更新用户级 Understand Anything Skills。" | jobs_intro_style body
  print -r -- "额度提醒：真正执行 /understand 时会消耗 Codex/AI 额度，本脚本不把它挂到 pod install。" | jobs_intro_style body
  print -r -- "日志位置：确认继续后，输出写入系统临时目录中的 ${SCRIPT_BASENAME}.log。" | jobs_intro_style body
  print -r -- "取消方式：此时按 Ctrl+C 终止，不会进入后续业务。" | jobs_intro_style body
  print -r -- "============================================================================" | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前没有可交互终端，请双击脚本或在 Terminal 中运行。"
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}

# 在用户通过自述确认后再初始化严格选项与日志，避免确认前产生副作用。
initialize_script_runtime() {
  set -u
  setopt NO_NOMATCH
  : >| "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

# 输出带时间戳的统一日志，便于终端和日志文件交叉排查。
log() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 输出流程分隔线，降低长路径和命令说明混在一起的阅读成本。
line() {
  print -r -- "────────────────────────────────────────────────────────────"
}

# 展示运行身份和日志位置，让用户在选择工程前确认脚本来源。
print_runtime_header() {
  clear 2>/dev/null || true
  print -r -- "🧠 ${APP_NAME}"
  print -r -- "用途：为自有或授权 Xcode/iOS 工程准备 Understand Anything 中文代码图谱"
  line
  log "脚本路径：${SCRIPT_PATH}"
  log "脚本目录：${SCRIPT_DIR}"
  log "日志文件：${LOG_FILE}"
  line
}

# 清理 Finder 拖入路径的引号、转义和 file URL，保留真实目录语义。
normalize_user_path() {
  local raw="$1"
  raw="${raw#${raw%%[![:space:]]*}}"
  raw="${raw%${raw##*[![:space:]]}}"
  raw="${(Q)raw}"
  if [[ "$raw" == file://* ]]; then
    raw="${raw#file://}"
    if [[ -x "${JOBS_PYTHON_BIN:-}" ]]; then
      raw="$("$JOBS_PYTHON_BIN" -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>/dev/null || print -r -- "$raw")"
    fi
  fi
  if [[ "$raw" == "~" || "$raw" == ~/* ]]; then
    raw="${raw/#\~/$HOME}"
  fi
  print -r -- "$raw"
}

# 判断输入是否直接指向 Xcode workspace 或 project 包。
is_xcode_item_path() {
  local target_path="$1"
  local lower="${target_path:l}"
  [[ -d "$target_path" && ( "$lower" == *.xcworkspace || "$lower" == *.xcodeproj ) ]]
}

# 只扫描候选目录第一层，避免误选 Pods、示例子工程或其它仓库。
scan_xcode_items_in_dir() {
  local dir="$1"
  local item=""
  XCODE_ITEMS=()
  [[ -d "$dir" ]] || return 1
  while IFS= read -r item; do
    [[ -n "$item" ]] && XCODE_ITEMS+=("$item")
  done < <(find "$dir" -maxdepth 1 -type d -iname "*.xcworkspace" -print 2>/dev/null | sort)
  while IFS= read -r item; do
    [[ -n "$item" ]] && XCODE_ITEMS+=("$item")
  done < <(find "$dir" -maxdepth 1 -type d -iname "*.xcodeproj" -print 2>/dev/null | sort)
  (( ${#XCODE_ITEMS[@]} > 0 ))
}

# 打印候选工程包，避免只凭目录名误判项目根目录。
print_found_xcode_items() {
  local root="$1"
  local item=""
  line
  log "✅ 找到候选 Xcode/iOS 工程根目录：${root}"
  for item in "${XCODE_ITEMS[@]}"; do
    print -r -- "  - $(basename "$item")"
  done
  line
}

# 让用户确认自动命中的目录，输入任意字符可继续寻找其它候选项。
confirm_project_root() {
  local root="$1"
  local answer=""
  print_found_xcode_items "$root"
  read -r "?直接回车确认；输入任意字符后回车继续选择：" answer
  [[ -z "$answer" ]]
}

# 验证目录并在用户确认后写入唯一工程根目录。
try_set_project_root_from_dir() {
  local dir="$1"
  dir="${dir:A}"
  if scan_xcode_items_in_dir "$dir" && confirm_project_root "$dir"; then
    PROJECT_ROOT="$dir"
    return 0
  fi
  return 1
}

# 同时支持工程根目录、workspace 和 project 三种拖入输入。
try_set_project_root_from_input_path() {
  local candidate="$1"
  if is_xcode_item_path "$candidate"; then
    try_set_project_root_from_dir "${candidate:h}"
    return $?
  fi
  if [[ -d "$candidate" ]]; then
    try_set_project_root_from_dir "$candidate"
    return $?
  fi
  log "❌ 路径不存在，或不是目录 / .xcworkspace / .xcodeproj：${candidate}"
  return 1
}

# 从脚本目录逐层向上寻找工程，修复脚本位于 ScriptsByDevTools 时只查一级的问题。
try_set_project_root_from_ancestors() {
  local current="$SCRIPT_DIR"
  local level=0
  while (( level < 8 )); do
    log "自动检查第 $((level + 1)) 层：${current}"
    if try_set_project_root_from_dir "$current"; then
      return 0
    fi
    [[ "$current" == "/" ]] && break
    current="${current:h}"
    (( level += 1 ))
  done
  return 1
}

# 自动定位失败时循环接收人工路径，直到确认有效工程。
prompt_for_project_root() {
  local raw=""
  while true; do
    print
    print -r -- "请输入或拖入：工程根目录、.xcworkspace 或 .xcodeproj。"
    read -r "?路径：" raw
    raw="$(normalize_user_path "$raw")"
    if [[ -z "$raw" ]]; then
      log "未输入路径，请重新输入。"
      continue
    fi
    if try_set_project_root_from_input_path "$raw"; then
      return 0
    fi
    log "未能确认有效工程，请重新输入。"
  done
}

# 优先使用命令行参数，其次逐层向上扫描，最后进入人工选择。
locate_project_root_or_exit() {
  local supplied_path="${1:-}"
  line
  log "开始定位 Xcode/iOS 工程根目录。"
  if [[ -n "$supplied_path" ]]; then
    supplied_path="$(normalize_user_path "$supplied_path")"
    if try_set_project_root_from_input_path "$supplied_path"; then
      return 0
    fi
    log "命令行参数未通过确认，继续自动扫描。"
  fi
  if try_set_project_root_from_ancestors; then
    return 0
  fi
  prompt_for_project_root || exit 1
}

# 验证 Codex CLI 是否可调用，缺失时只提示官方入口，不代替用户安装。
ensure_codex_cli_or_exit() {
  line
  log "开始 Codex CLI 健康体检。"
  if ! command -v codex >/dev/null 2>&1; then
    log "❌ 未找到 codex 命令。请先从 OpenAI 官方渠道安装 Codex CLI。"
    log "官方说明：https://developers.openai.com/codex/cli"
    finish_and_wait 1
  fi
  log "✅ Codex 路径：$(command -v codex)"
  local version="$(codex --version 2>/dev/null | head -n 1 || true)"
  [[ -n "$version" ]] && log "Codex 版本：${version}"
}

# 对安装和升级动作统一采用“回车跳过、输入任意字符执行”的保守交互。
ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}

# 下载到独立临时目录并记录哈希，避免直接执行 curl 管道导致内容不可审计。
install_understand_anything_for_codex() {
  local temp_dir=""
  local installer=""
  line
  if ! ask_any_to_run "未检测到 Understand Anything，是否从官方仓库安装"; then
    log "已跳过安装；不会启动 Codex 或生成图谱。"
    finish_and_wait 0
  fi
  command -v curl >/dev/null 2>&1 || { log "❌ 未找到 curl。"; finish_and_wait 1; }
  temp_dir="$(mktemp -d "${TMPDIR%/}/understand-anything.XXXXXX")" || { log "❌ 无法创建临时目录。"; finish_and_wait 1; }
  installer="${temp_dir}/install.sh"
  log "下载安装脚本：${UA_INSTALL_URL}"
  if ! curl --proto '=https' --tlsv1.2 -fsSL "$UA_INSTALL_URL" -o "$installer"; then
    rmdir "$temp_dir" 2>/dev/null || true
    log "❌ 安装脚本下载失败。"
    finish_and_wait 1
  fi
  log "安装脚本 SHA-256：$(shasum -a 256 "$installer" | awk '{print $1}')"
  /bin/bash "$installer" codex
  local code=$?
  rm -f -- "$installer"
  rmdir "$temp_dir" 2>/dev/null || true
  if (( code != 0 )); then
    log "❌ Understand Anything 安装失败，退出码：${code}"
    finish_and_wait "$code"
  fi
}

# 展示当前提交并由用户决定是否调用仓库自带升级入口。
upgrade_understand_anything_if_requested() {
  local branch=""
  local commit=""
  branch="$(git -C "$UA_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  commit="$(git -C "$UA_REPO" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] && log "Understand Anything 分支：${branch}"
  [[ -n "$commit" ]] && log "Understand Anything 提交：${commit}"
  if ! ask_any_to_run "Understand Anything 已安装，是否执行官方升级"; then
    log "已跳过 Understand Anything 升级。"
    return 0
  fi
  if [[ ! -f "$UA_REPO/install.sh" ]]; then
    log "❌ 安装目录缺少 install.sh，停止自动修复，请先检查目录来源。"
    finish_and_wait 1
  fi
  (
    cd "$UA_REPO" || exit 1
    /bin/bash ./install.sh --update
  )
  local code=$?
  if (( code != 0 )); then
    log "❌ Understand Anything 升级失败，退出码：${code}"
    finish_and_wait "$code"
  fi
  log "✅ Understand Anything 升级完成。"
}

# 检查仓库和用户级 Skill 链接，确保安装结果可被新的 Codex 会话加载。
validate_understand_anything_installation_or_exit() {
  if [[ ! -d "$UA_REPO" || ! -f "$UA_REPO/install.sh" ]]; then
    log "❌ 未检测到完整安装目录：${UA_REPO}"
    finish_and_wait 1
  fi
  log "✅ Understand Anything 仓库：${UA_REPO}"
  local skill_count=0
  local skill_path=""
  while IFS= read -r skill_path; do
    [[ -n "$skill_path" ]] || continue
    print -r -- "  - ${skill_path} -> $(readlink "$skill_path" 2>/dev/null || print -r -- '非符号链接')"
    (( skill_count += 1 ))
  done < <(find "$HOME/.agents/skills" -maxdepth 1 -name 'understand*' -print 2>/dev/null | sort)
  if (( skill_count == 0 )); then
    log "⚠️ 未在用户级 Skills 目录发现 understand* 项；重启 Codex 后若命令不可见，请重新执行安装。"
  else
    log "✅ 检测到 ${skill_count} 个 Understand Anything Skill 入口。"
  fi
}

# 按“已安装则可选升级、未安装则可选安装”的顺序完成健康体检。
ensure_understand_anything_or_exit() {
  line
  log "开始 Understand Anything 健康体检。"
  if [[ -d "$UA_REPO" && -f "$UA_REPO/install.sh" ]]; then
    upgrade_understand_anything_if_requested
  else
    install_understand_anything_for_codex
  fi
  validate_understand_anything_installation_or_exit
}

# 输出当前官方命令地图，明确生成图谱仍需用户进入 Codex 后主动执行。
print_understand_anything_usage() {
  line
  log "工程根目录：${PROJECT_ROOT}"
  print -r -- ""
  print -r -- "重新启动 Codex 后，在工程根目录按需要执行："
  print -r -- "  /understand --language zh      # 生成或增量更新代码知识图谱"
  print -r -- "  /understand-dashboard          # 打开交互式图谱"
  print -r -- "  /understand-chat               # 基于图谱提问"
  print -r -- "  /understand-diff               # 分析 Git 变更影响"
  print -r -- "  /understand-explain            # 深入解释文件、函数或模块"
  print -r -- "  /understand-onboard            # 生成项目入门指南"
  print -r -- "  /understand-domain             # 提取业务领域关系"
  print -r -- ""
  print -r -- "图谱通常位于：${PROJECT_ROOT}/.understand-anything/knowledge-graph.json"
  print -r -- "大型项目可先限定自有源码目录；默认增量分析，不要挂接高频构建或 pod install。"
  line
}

# 仅在用户主动输入内容时启动 Codex，直接回车保持无副作用结束。
offer_to_launch_codex() {
  if ! ask_any_to_run "是否现在进入工程根目录并启动 Codex"; then
    log "已选择不启动 Codex。"
    return 0
  fi
  log "进入工程根目录并启动 Codex：${PROJECT_ROOT}"
  cd "$PROJECT_ROOT" || { log "❌ 无法进入工程根目录。"; return 1; }
  codex
}

# 汇总使用说明并把启动动作留给用户最终确认。
show_usage_and_offer_launch() {
  print_understand_anything_usage
  if ! offer_to_launch_codex; then
    log "❌ Codex 启动流程失败。"
    finish_and_wait 1
  fi
}

# 统一输出退出码和日志路径，交互终端中等待用户确认后关闭窗口。
finish_and_wait() {
  local code="${1:-0}"
  print
  log "脚本流程结束，退出码：${code}"
  log "完整日志：${LOG_FILE}"
  read -r "?按回车退出：" _
  exit "$code"
}

# 主入口只编排高层业务动作，具体控制和异常收口由各函数负责。
# 入口失败在阶段内终止；source 业务继续使用可返回的预检函数。
jobs_ios_python_prepare_runtime() {
  jobs_ios_python_preflight confirmed || exit 1
}


main() {
  show_script_intro_and_wait "$@" # 先完成无副作用的三层自述确认
  jobs_ios_python_prepare_runtime # 业务确认后使用内嵌函数准备 Homebrew Python。
  initialize_script_runtime # 用户确认后初始化严格选项与日志
  print_runtime_header # 展示脚本身份、路径和日志位置
  locate_project_root_or_exit "$@" # 定位并确认 Xcode/iOS 工程根目录
  ensure_codex_cli_or_exit # 验证 Codex CLI 可用性
  ensure_understand_anything_or_exit # 可选安装或升级并验证 Skill 入口
  show_usage_and_offer_launch # 说明命令并由用户决定是否启动 Codex
  finish_and_wait 0 # 汇总日志并安全退出
}

main "$@"
