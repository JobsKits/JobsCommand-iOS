#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@Xcode】🫘当前工程Pod Install.command
# - 核心用途：识别 Xcode 当前工程，在独立终端确认后执行 pod install。
# - 影响范围：目标 Podfile 可下载依赖、更新工作区并执行自身安装 hooks。
# - 运行提示：精确输入 INSTALL 后回车安装；其它输入或 Ctrl+C 取消，--check 只检查目标。
# shell: zsh

SCRIPT_PATH="$0"
XCODE_PATH=""
PROJECT_ROOT=""
LOG_FILE=""
POD_EXECUTABLE=""
CHECK_ONLY=0
TERMINAL_HANDOFF=0
INTRO_COLOR=0

# 明确报错并停止，避免在未知工程中继续安装。
fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit "${2:-1}"
}
# 展示手动入口与只读检查参数。
show_usage() {
  printf '%s\n' \
    '用法：由 Xcode Behavior 直接调用，自动读取 XcodeWorkspacePath。' \
    '终端指定：脚本 --xcode-path /完整路径/App.xcworkspace' \
    '只读检查：脚本 --check [--xcode-path /完整路径/App.xcodeproj]' \
    '无工程上下文时停止，不按工作目录或历史工程猜测目标。'
}
# 解析展示参数，优先使用 Xcode 本次调用传入的工作区。
prepare_display_context() {
  SCRIPT_PATH="${SCRIPT_PATH:A}"
  while (( $# )); do
    case "$1" in
      --xcode-path)
        (( $# >= 2 )) || fail '--xcode-path 缺少工程路径。' 64
        [[ -z "$XCODE_PATH" ]] || fail '不能重复指定工程路径。' 64
        XCODE_PATH="$2"
        shift 2
        ;;
      --check)
        CHECK_ONLY=1
        shift
        ;;
      --terminal)
        TERMINAL_HANDOFF=1
        shift
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      *) fail "未知参数：$1" 64 ;;
    esac
  done
  if [[ -z "$XCODE_PATH" ]]; then
    XCODE_PATH="${XcodeWorkspacePath:-${XcodeProjectPath:-}}"
  fi
  [[ -n "$XCODE_PATH" ]] || fail '未取得 Xcode 当前工程；请激活工程窗口后重试，或用 --xcode-path 明确指定。' 64
  [[ "$XCODE_PATH" == /* && -d "$XCODE_PATH" ]] || fail "工程路径不存在或不是绝对路径：$XCODE_PATH" 66
  XCODE_PATH="${XCODE_PATH:A}"
  if [[ "$XCODE_PATH" == *.xcodeproj/project.xcworkspace ]]; then
    XCODE_PATH="${XCODE_PATH:h}"
  fi
  [[ "$XCODE_PATH" == *.xcworkspace || "$XCODE_PATH" == *.xcodeproj ]] || fail '只接受 .xcworkspace 或 .xcodeproj 工程。' 64
  [[ "${XCODE_PATH:t}" != Pods.xcodeproj && "$XCODE_PATH" != */Pods/* && "$XCODE_PATH" != */.swiftpm/* ]] || fail '当前是 Pods 或 Swift Package 生成工程，请切回 iOS App 工程窗口。' 64
  resolve_project_directory
  validate_declared_platform
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    INTRO_COLOR=1
  fi
}
# 只在当前工程的祖先目录寻找最近的 Podfile，不跨仓或递归其它工程。
resolve_project_directory() {
  local candidate="${XCODE_PATH:h}"
  while [[ "$candidate" != / && "$candidate" != "${HOME:-/}" ]]; do
    if [[ -f "$candidate/Podfile" ]]; then
      PROJECT_ROOT="$candidate"
      return 0
    fi
    [[ ! -e "$candidate/.git" ]] || break
    candidate="${candidate:h}"
  done
  fail "当前工程及仓库内的上级目录没有 Podfile：$XCODE_PATH" 66
}
# 只拒绝明确的非 iOS 声明，不执行 Podfile 来推断动态 Ruby 配置。
validate_declared_platform() {
  /usr/bin/awk '
    /^[[:space:]]*platform[[:space:](]+:ios([[:space:],)]|$)/ { ios = 1 }
    /^[[:space:]]*platform[[:space:](]+:(osx|macos|tvos|watchos|visionos)([[:space:],)]|$)/ { other = 1 }
    END { exit (other && !ios) ? 1 : 0 }
  ' "$PROJECT_ROOT/Podfile" || fail 'Podfile 明确声明为非 iOS 平台，请切回 iOS App 工程。' 64
}
# 保持标题与正文层级，非彩色环境不输出 ANSI。
print_intro_line() {
  if (( INTRO_COLOR )); then
    if [[ "$1" == title ]]; then
      printf '\033[1;31m%s\033[0m\n' "$2"
    else
      printf '\033[0;34m%s\033[0m\n' "$2"
    fi
  else
    printf '%s\n' "$2"
  fi
}
# 展示精确目标并等待终端确认，只读检查在此安全结束。
show_script_intro_and_wait() {
  prepare_display_context "$@"
  print_intro_line title '🫘 当前工程 · Pod Install'
  print_intro_line body "1、Xcode 工程：$XCODE_PATH"
  print_intro_line body "2、Podfile 目录：$PROJECT_ROOT"
  print_intro_line body '3、确认后执行 pod install；安装 hooks 由目标 Podfile 决定。'
  print_intro_line body '4、只检查现有 CocoaPods，不安装或升级工具链；完整日志保存在系统临时目录。'
  if (( CHECK_ONLY )); then
    print_intro_line body '5、只读检查通过；未运行 pod、未写入日志或工程文件。'
    exit 0
  fi
  if [[ ! -t 0 ]]; then
    (( TERMINAL_HANDOFF == 0 )) || fail '终端没有可交互输入，已停止。' 64
    print_intro_line body '5、正在打开 Terminal；核对目标后输入 INSTALL 再回车安装，其它输入或 Ctrl+C 取消。'
    open_terminal_and_run_script
    exit $?
  fi
  print_intro_line body '5、核对目标后精确输入 INSTALL 再回车；空行、其它输入或 Ctrl+C 均取消。'
  local install_confirmation=""
  if ! IFS= read -r 'install_confirmation?👉 确认目标后输入 INSTALL：' < /dev/tty || [[ "$install_confirmation" != INSTALL ]]; then
    printf '\n%s\n' '[WARN] 未取得 INSTALL 确认，已停止。' >&2
    exit 130
  fi
}
# 用私有临时启动器传递目标，避免已运行的 Terminal 丢失 Xcode 环境。
open_terminal_and_run_script() {
  local handoff_dir=""
  local handoff_file=""
  local launch_exit=0
  umask 077
  handoff_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-xcode-pod-handoff.XXXXXX")" || fail '无法准备终端启动器。'
  handoff_file="$handoff_dir/Pod Install.command"
  if ! {
    printf '%s\n' '#!/bin/zsh' \
      '# 一次性启动器只传递工程路径；安装仍由通用入口确认。' \
      '/bin/rm -f -- "${0:A}"' \
      '/bin/rmdir -- "${0:A:h}" 2>/dev/null'
    printf 'exec /bin/zsh %q --terminal --xcode-path %q\n' "$SCRIPT_PATH" "$XCODE_PATH"
  } > "$handoff_file" || ! /bin/chmod 700 "$handoff_file"; then
    /bin/rm -f -- "$handoff_file"
    /bin/rmdir -- "$handoff_dir"
    fail '无法写入终端启动器。'
  fi
  /usr/bin/open -b com.apple.Terminal "$handoff_file"
  launch_exit=$?
  if (( launch_exit != 0 )); then
    /bin/rm -f -- "$handoff_file"
    /bin/rmdir -- "$handoff_dir"
    fail "无法打开 Terminal，退出码：$launch_exit" "$launch_exit"
  fi
  printf '%s\n' '[INFO] 已打开终端等待确认；结果以终端及本次日志为准。'
}
# 确认后建立独立日志，防止多个工程的输出互相覆盖。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/jobs-xcode-pod-install.log.XXXXXX")" || fail '无法创建安装日志。'
  trap 'printf "\n[WARN] 安装已取消。\n" | /usr/bin/tee -a "$LOG_FILE"; exit 130' INT
  [[ -f "$PROJECT_ROOT/Podfile" && -d "$XCODE_PATH" ]] || fail '确认期间工程或 Podfile 已移除，已停止。' 66
  cd -- "$PROJECT_ROOT" || fail "无法进入项目目录：$PROJECT_ROOT"
  log "[INFO] Xcode 工程：$XCODE_PATH"
  log "[INFO] Podfile 目录：$PROJECT_ROOT"
  log "[INFO] 完整安装日志：$LOG_FILE"
}
# 同步终端与日志输出，日志不可写时停止。
log() {
  printf '%s\n' "$1" | /usr/bin/tee -a "$LOG_FILE"
  (( $? == 0 )) || fail "写入日志失败：$LOG_FILE"
}
# 复用现有 CocoaPods，缺失或损坏时停止而不自动安装工具链。
check_pod_environment() {
  POD_EXECUTABLE="$(command -v pod)"
  if [[ -z "$POD_EXECUTABLE" ]]; then
    export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"
    rehash
    POD_EXECUTABLE="$(command -v pod)"
  fi
  [[ -n "$POD_EXECUTABLE" ]] || fail '未找到 pod；请先在普通终端配置 CocoaPods 后重试。' 127
  log "[INFO] CocoaPods 入口：$POD_EXECUTABLE"
  "$POD_EXECUTABLE" --version 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local -a check_codes=("${pipestatus[@]}")
  (( check_codes[1] == 0 && check_codes[2] == 0 )) || fail "pod 健康检查失败：pod=${check_codes[1]}，日志=${check_codes[2]}。"
}
# 保留安装与日志写入的真实退出码，不掩盖失败。
run_pod_install() {
  log '[INFO] 开始执行：pod install'
  "$POD_EXECUTABLE" install 2>&1 | /usr/bin/tee -a "$LOG_FILE"
  local -a install_codes=("${pipestatus[@]}")
  local install_exit="${install_codes[1]}"
  if (( install_codes[2] != 0 )); then
    printf '[ERROR] 安装日志写入失败：%s\n' "$LOG_FILE" >&2
    (( install_exit == 0 )) && install_exit=1
  fi
  if (( install_exit == 0 )); then
    log '[OK] pod install 已完成，退出码：0。'
  else
    log "[ERROR] pod install 失败，退出码：$install_exit。"
  fi
  log "[INFO] 完整安装日志：$LOG_FILE"
  exit "$install_exit"
}
# 编排当前工程识别、终端确认和依赖安装。
main() {
  show_script_intro_and_wait "$@" # 显示当前工程并在终端确认，检查模式到此结束。
  initialize_script_runtime # 确认后建立独立日志并进入目标目录。
  check_pod_environment # 检查现有 CocoaPods 是否可用。
  run_pod_install # 执行安装并保留真实退出码。
}

main "$@"
