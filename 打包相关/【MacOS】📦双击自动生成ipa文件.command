#!/bin/zsh
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
info_echo()    { _color "34" "ℹ️  $*"; }
success_echo() { _color "32" "✅ $*"; }
warn_echo()    { _color "33" "⚠️  $*"; }
err_echo()     { _color "31" "❌ $*"; }

log() {
  local ts
  ts="$(/bin/date '+%F %T' 2>/dev/null || echo '0000-00-00 00:00:00')"
  printf "%s %s\n" "$ts" "$*" >> "$LOG_FILE"
}

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

list_schemes_text() {
  local proj="$1" out
  out="$(xcodebuild_list_raw "$proj" || true)"
  [[ -n "$out" ]] || return 1
  printf "%s\n" "$out" | /usr/bin/awk '
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

filter_main_schemes() { /usr/bin/awk '/^B($|_)/{print}'; }

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
