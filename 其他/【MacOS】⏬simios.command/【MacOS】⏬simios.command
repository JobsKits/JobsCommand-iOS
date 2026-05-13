#!/bin/zsh

emulate -R zsh
set -eu
set -o pipefail
setopt NULL_GLOB

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_MAGENTA='\033[35m'
C_RED='\033[31m'
C_GRAY='\033[90m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
LOG_DIR="${HOME}/Library/Logs/simios"
LOG_FILE="${LOG_DIR}/simios-$(date '+%Y%m%d-%H%M%S').log"

XCODE_APP=""
DEVELOPER_DIR_SELECTED=""
XCODEBUILD_BIN=""
VERBOSE_ARG=""

cecho() {
  local color="$1"
  shift
  printf "%b%s%b\n" "$color" "$*" "$C_RESET"
}

line() {
  cecho "$C_GRAY" "────────────────────────────────────────"
}

section() {
  echo ""
  cecho "$C_BOLD$C_CYAN" "▶ $1"
  line
}

log() {
  cecho "$C_BLUE" "[simios] $1"
}

ok() {
  cecho "$C_GREEN" "[OK] $1"
}

warn() {
  cecho "$C_YELLOW" "[WARN] $1"
}

err() {
  cecho "$C_RED" "[ERR] $1"
}

pause_enter() {
  local message="${1:-按回车继续...}"
  printf "%b%s%b" "$C_MAGENTA" "$message" "$C_RESET"
  local _input=""
  IFS= read -r _input
}

ask_run() {
  local message="$1"
  local input=""
  printf "%b%s%b" "$C_MAGENTA" "${message}（回车跳过，输入任意字符后回车执行）：" "$C_RESET"
  IFS= read -r input
  [[ -n "$input" ]]
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

show_readme_and_wait() {
  clear || true
  cecho "$C_BOLD$C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cecho "$C_BOLD$C_CYAN" "        simios.command"
  cecho "$C_BOLD$C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cecho "$C_BLUE" "用途：检测 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。"
  echo ""
  cecho "$C_GREEN" "执行顺序："
  cecho "$C_GRAY" "  1) 检测 macOS / Xcode.app 是否存在"
  cecho "$C_GRAY" "  2) 检测 xcodebuild 是否来自完整 Xcode，而不是只有 Command Line Tools"
  cecho "$C_GRAY" "  3) 检测 xcode-select 指向；不强制永久改系统，可临时使用 DEVELOPER_DIR"
  cecho "$C_GRAY" "  4) 检测 Xcode 首次启动组件 / license / 磁盘空间 / 网络连通"
  cecho "$C_GRAY" "  5) 最后由你决定是否执行 iOS 模拟器下载"
  echo ""
  cecho "$C_YELLOW" "交互规则："
  cecho "$C_GRAY" "  - 普通安装 / 更新动作：回车跳过，输入任意字符后回车执行"
  cecho "$C_GRAY" "  - 必须修复项：脚本会明确说明原因，再让你继续"
  echo ""
  cecho "$C_GREEN" "核心下载命令："
  cecho "$C_GRAY" "  xcodebuild -downloadPlatform iOS -verbose"
  echo ""
  cecho "$C_YELLOW" "说明："
  cecho "$C_GRAY" "  xcodebuild 官方帮助里通常是单横线 -verbose；如果你的版本支持 --verbose，脚本会自动使用 --verbose。"
  echo ""
  pause_enter "按回车开始体检..."
}

require_macos() {
  section "系统检测"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "当前不是 macOS，无法下载 Xcode iOS Simulator Runtime。"
    exit 1
  fi

  ok "当前系统是 macOS。"
}

collect_xcode_apps() {
  local -a found
  local item=""

  for item in \
    /Applications/Xcode.app \
    /Applications/Xcode*.app \
    "${HOME}/Applications/Xcode.app" \
    "${HOME}/Applications/Xcode"*.app \
    /Applications/Xcodes/Xcode*.app; do
    if [[ -d "${item}/Contents/Developer" && -x "${item}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      found+=("$item")
    fi
  done

  if (( ${#found[@]} > 0 )); then
    printf "%s\n" "${found[@]}" | awk '!seen[$0]++'
  fi
}

choose_xcode_app() {
  section "Xcode 检测"

  local active_dev=""
  local active_app=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  if [[ "$active_dev" == */Contents/Developer ]]; then
    active_app="${active_dev%/Contents/Developer}"
    if [[ -d "$active_app" && -x "${active_app}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      XCODE_APP="$active_app"
      ok "当前 xcode-select 已指向完整 Xcode：$XCODE_APP"
      return 0
    fi
  fi

  local first_app=""
  first_app="$(collect_xcode_apps | head -n 1)"

  if [[ -z "$first_app" ]]; then
    err "未检测到完整 Xcode.app。"
    warn "只安装 Command Line Tools 没有现实意义：iOS Simulator Runtime 下载依赖完整 Xcode。"
    warn "请先安装 Xcode，再重新运行：$SCRIPT_PATH"
    echo ""
    cecho "$C_GRAY" "建议路径：/Applications/Xcode.app"
    cecho "$C_GRAY" "安装来源：Mac App Store 或 Apple Developer 下载页"
    exit 1
  fi

  XCODE_APP="$first_app"
  ok "检测到 Xcode：$XCODE_APP"
}

maybe_check_xcode_update() {
  echo ""
  if ask_run "Xcode 已存在，是否打开更新入口检查 Xcode 升级"; then
    if command -v mas >/dev/null 2>&1; then
      log "检测到 mas，尝试升级 App Store 版 Xcode。"
      mas upgrade 497799835 || open "macappstore://itunes.apple.com/app/id497799835" || true
    else
      warn "未检测到 mas。为了避免额外引入 Homebrew / mas，本脚本不自动安装它。"
      log "改为打开 App Store 的 Xcode 页面。"
      open "macappstore://itunes.apple.com/app/id497799835" || true
    fi
  else
    log "跳过 Xcode 升级检查。"
  fi
}

prepare_developer_dir() {
  section "xcode-select / DEVELOPER_DIR 检测"

  DEVELOPER_DIR_SELECTED="${XCODE_APP}/Contents/Developer"
  XCODEBUILD_BIN="${DEVELOPER_DIR_SELECTED}/usr/bin/xcodebuild"

  if [[ ! -x "$XCODEBUILD_BIN" ]]; then
    err "xcodebuild 不存在或不可执行：$XCODEBUILD_BIN"
    exit 1
  fi

  export DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED"

  local active_dev=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  ok "本次脚本使用：DEVELOPER_DIR=$DEVELOPER_DIR_SELECTED"

  if [[ "$active_dev" == "$DEVELOPER_DIR_SELECTED" ]]; then
    ok "系统 xcode-select 指向正确。"
  else
    warn "系统 xcode-select 当前指向：${active_dev:-未设置}"
    warn "脚本本次会临时使用 DEVELOPER_DIR，不强制修改你的全局设置。"
    if ask_run "是否永久切换 xcode-select 到当前 Xcode"; then
      run_root xcode-select -s "$DEVELOPER_DIR_SELECTED"
      ok "已永久切换 xcode-select。"
    else
      log "跳过永久切换，仅本次脚本临时使用当前 Xcode。"
    fi
  fi
}

show_xcode_version() {
  section "Xcode 版本"
  "$XCODEBUILD_BIN" -version || {
    err "xcodebuild 无法正常输出版本。"
    exit 1
  }
}

check_xcodebuild_support() {
  section "xcodebuild 能力检测"

  local help_text=""
  help_text="$({ "$XCODEBUILD_BIN" -help || true; } 2>&1)"

  if ! printf "%s\n" "$help_text" | grep -q -- "downloadPlatform"; then
    err "当前 Xcode 的 xcodebuild 不支持 -downloadPlatform。"
    warn "这通常说明 Xcode 版本过旧，需要先升级 Xcode。"
    maybe_check_xcode_update
    exit 1
  fi

  ok "支持 -downloadPlatform。"

  if printf "%s\n" "$help_text" | grep -q -- "--verbose"; then
    VERBOSE_ARG="--verbose"
  else
    VERBOSE_ARG="-verbose"
  fi

  ok "verbose 参数使用：$VERBOSE_ARG"
}

ensure_first_launch() {
  section "Xcode 首次启动组件检测"

  local help_text=""
  help_text="$({ "$XCODEBUILD_BIN" -help || true; } 2>&1)"

  if printf "%s\n" "$help_text" | grep -q -- "checkFirstLaunchStatus"; then
    if "$XCODEBUILD_BIN" -checkFirstLaunchStatus >/dev/null 2>&1; then
      ok "Xcode 首次启动组件状态正常。"
    else
      warn "Xcode 首次启动组件未完成。"
      warn "这属于执行 xcodebuild 下载前的必要支援项，需要安装 / 初始化。"
      pause_enter "按回车执行：sudo xcodebuild -runFirstLaunch ..."
      run_root "$XCODEBUILD_BIN" -runFirstLaunch
      ok "首次启动组件已处理。"
    fi
  else
    warn "当前 xcodebuild 不支持 -checkFirstLaunchStatus。"
    if ask_run "是否执行一次 xcodebuild -runFirstLaunch 做初始化"; then
      run_root "$XCODEBUILD_BIN" -runFirstLaunch
      ok "已执行首次启动初始化。"
    else
      log "跳过首次启动初始化。"
    fi
  fi
}

ensure_license() {
  section "Xcode License 检测"

  if "$XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    ok "Xcode license 已同意。"
    return 0
  fi

  warn "Xcode license 尚未同意。"
  warn "不同意 license 时，xcodebuild 后续下载大概率会失败。"
  pause_enter "按回车进入交互式 license 确认：sudo xcodebuild -license ..."
  run_root "$XCODEBUILD_BIN" -license

  if "$XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    ok "Xcode license 已同意。"
  else
    err "license 仍未通过检查，停止执行。"
    exit 1
  fi
}

check_disk_space() {
  section "磁盘空间检测"

  local free_kb="0"
  local free_gb="0"
  free_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
  free_gb=$(( free_kb / 1024 / 1024 ))

  if (( free_gb >= 30 )); then
    ok "当前用户目录所在磁盘可用空间约 ${free_gb}GB。"
  elif (( free_gb >= 15 )); then
    warn "当前可用空间约 ${free_gb}GB，可能够用，但大型 runtime 可能吃紧。"
  else
    warn "当前可用空间约 ${free_gb}GB，iOS Simulator Runtime 下载很可能失败。"
  fi
}

check_network() {
  section "网络连通检测"

  if ! command -v curl >/dev/null 2>&1; then
    warn "未检测到 curl，跳过网络预检。macOS 正常情况下会自带 curl。"
    return 0
  fi

  if curl -Is --connect-timeout 10 https://developer.apple.com >/dev/null 2>&1; then
    ok "developer.apple.com 可连接。"
  else
    warn "developer.apple.com 连接预检失败。可能是网络、代理、VPN、DNS 或 Apple CDN 临时问题。"
    warn "这不是本地环境硬缺失，脚本不会自动改网络设置。"
  fi
}

list_ios_runtimes() {
  if DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl runtime list >/dev/null 2>&1; then
    DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl runtime list 2>/dev/null | grep -i "iOS" || true
  else
    DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" || true
  fi
}

show_existing_runtimes() {
  section "现有 iOS Runtime"

  local runtimes=""
  runtimes="$(list_ios_runtimes)"

  if [[ -n "$runtimes" ]]; then
    ok "检测到 iOS Runtime："
    printf "%s\n" "$runtimes"
  else
    warn "未检测到 iOS Runtime，稍后建议执行下载。"
  fi
}

run_download() {
  section "下载 / 补齐 iOS Simulator Runtime"

  mkdir -p "$LOG_DIR"

  cecho "$C_GRAY" "日志文件：$LOG_FILE"
  cecho "$C_GRAY" "将执行：xcodebuild -downloadPlatform iOS $VERBOSE_ARG"
  echo ""

  if ! ask_run "是否开始下载 / 补齐 iOS Simulator Runtime"; then
    log "已跳过下载。"
    return 0
  fi

  local -a args
  args=(-downloadPlatform iOS "$VERBOSE_ARG")

  set +e
  DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" "$XCODEBUILD_BIN" "${args[@]}" 2>&1 | tee "$LOG_FILE"
  local status=${pipestatus[1]}
  set -e

  if (( status != 0 )); then
    err "下载命令失败，退出码：$status"
    warn "完整日志：$LOG_FILE"
    warn "常见原因：license 未同意、Xcode 未完成首次启动、网络 / CDN 异常、磁盘空间不足、Xcode 版本过旧。"
    exit "$status"
  fi

  ok "iOS Simulator Runtime 下载 / 补齐命令执行完成。"
}

final_report() {
  section "完成报告"

  ok "脚本执行结束。"
  cecho "$C_GRAY" "脚本路径：$SCRIPT_PATH"
  cecho "$C_GRAY" "日志路径：$LOG_FILE"
  echo ""
  cecho "$C_GREEN" "当前 iOS Runtime："
  list_ios_runtimes || true
  echo ""
  cecho "$C_GRAY" "如果 Xcode UI 里暂时看不到新 runtime，重启 Xcode 后再看。"
}

main() {
  show_readme_and_wait
  require_macos
  choose_xcode_app
  maybe_check_xcode_update
  prepare_developer_dir
  show_xcode_version
  check_xcodebuild_support
  ensure_first_launch
  ensure_license
  check_disk_space
  check_network
  show_existing_runtimes
  run_download
  final_report
  pause_enter "按回车退出..."
}

main "$@"
