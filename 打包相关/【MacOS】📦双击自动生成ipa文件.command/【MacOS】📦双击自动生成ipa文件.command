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
  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ "$arch" == "arm64" && -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi
  [[ -z "$brew_bin" ]] && return 1

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
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

  if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="/usr/local/bin/brew"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || true
    return 0
  fi

  activate_homebrew_shellenv || true
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update
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
show_readme_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】📦双击自动生成ipa文件.command'
  print -r -- '核心用途：执行“📦双击自动生成ipa文件”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
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
    cat <<'EOF'
  📦==================================================
                  iOS IPA 打包助手
  ==================================================
  • 多 Target：用 fzf 选择要打的 Target/Scheme（默认只显示 B 系列）
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
    /bin/mkdir -p "$OUT_DIR"
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
  has_fzf() { /usr/bin/command -v fzf >/dev/null 2>&1; }
  # 封装 fzf_pick_one 对应的独立处理逻辑。
  fzf_pick_one() {
    local prompt="$1"
    if has_fzf; then
      fzf --prompt="$prompt" --height=40% --reverse
    else
      /usr/bin/awk 'NF{print; exit}'
    fi
  }
  # ================================== choose project/workspace ==================================
  choose_project_path() {
    local root="$1"

    if [[ -n "$PROJECT_PATH" ]]; then
      [[ -e "$PROJECT_PATH" ]] || { err_echo "--project 指定路径不存在：$PROJECT_PATH"; exit 1; }
      echo "$PROJECT_PATH"; return 0
    fi

    local ws_list pj_list picked
    ws_list="$(/usr/bin/find "$root" -maxdepth 12 -name "*.xcworkspace" -print 2>/dev/null | /usr/bin/awk '!/\.xcodeproj\/project\.xcworkspace$/')"
    pj_list="$(/usr/bin/find "$root" -maxdepth 12 -name "*.xcodeproj" -print 2>/dev/null)"

    if [[ -n "$ws_list" ]]; then
      picked="$(printf "%s\n" "$ws_list" | /usr/bin/awk '{print length($0) "\t" $0}' | /usr/bin/sort -n | /usr/bin/cut -f2- \
        | fzf_pick_one "选择 Workspace/Project > ")"
    else
      picked="$(printf "%s\n" "$pj_list" | /usr/bin/awk '{print length($0) "\t" $0}' | /usr/bin/sort -n | /usr/bin/cut -f2- \
        | fzf_pick_one "选择 Workspace/Project > ")"
    fi

    [[ -n "$picked" && -e "$picked" ]] || { err_echo "未找到可用的 .xcworkspace / .xcodeproj"; exit 1; }
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

    local all schemes scount
    all="$(list_schemes_text "$proj" || true)"
    schemes="$(printf "%s\n" "$all" | filter_main_schemes || true)"
    scount="$(printf "%s\n" "$schemes" | /usr/bin/awk 'NF{c++} END{print c+0}')"

    if [[ "$scount" -eq 0 ]]; then
      schemes="$all"
      scount="$(printf "%s\n" "$schemes" | /usr/bin/awk 'NF{c++} END{print c+0}')"
    fi

    [[ "$scount" -gt 0 ]] || { err_echo "未获取到任何 Scheme（看日志 $LOG_FILE）"; exit 1; }

    if [[ "$scount" -eq 1 ]]; then
      printf "%s\n" "$schemes"
      return 0
    fi

    printf "%s\n" "$schemes" | fzf_pick_one "选择要打包的 Scheme（优先 B 系列）> "
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

    local repo_root proj scheme app_path ipa_name ipa_path

    repo_root="$(find_repo_root)"
    info_echo "📂 工作目录：$repo_root"
    log "repo_root=$repo_root"
    log "PWD=$PWD  0=$0  x=${(%):-%x}"

    proj="$(choose_project_path "$repo_root")"
    success_echo "发现工程：$(basename "$proj")"
    log "project=$proj"

    scheme="$(choose_scheme "$proj")"
    success_echo "选择 scheme：$scheme"
    log "scheme=$scheme"

    maybe_confirm "$proj" "$scheme"

    app_path="$(get_app_path "$proj" "$scheme" || true)"
    [[ -n "$app_path" && -d "$app_path" ]] || { err_echo "未能定位 .app（看日志：$LOG_FILE）"; exit 1; }

    success_echo "已定位 .app：$app_path"
    log "app_path=$app_path"

    ipa_name="$(infer_ipa_name "$app_path" "$scheme")"
    ipa_path="${OUT_DIR}/${ipa_name}.ipa"

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
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
