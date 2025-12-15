#!/bin/zsh
# ===============================================================
#  package_ipa.command  (macOS / zsh)
# ---------------------------------------------------------------
#  功能：
#   • 从 Xcode DerivedData 中找到最新构建的 .app（真机目标）
#   • 打包为 .ipa，输出到指定目录（默认桌面）
#   • 支持参数：--config / --out / --project / --confirm
#  用法示例：
#   ./package_ipa.command --config Release --out ~/Desktop
#   ./package_ipa.command --project ./MyApp.xcodeproj --confirm
# ===============================================================

set -euo pipefail

# ============================ 配置默认值 ============================
CONFIG="Release"           # Debug / Release
OUT_DIR="${HOME}/Desktop"  # 输出目录
PROJECT_PATH=""            # 指定 .xcodeproj 或 .xcworkspace
CONFIRM="0"                # 交互确认：0=关闭(适配 SourceTree)，1=开启
LOG_FILE="/tmp/package_ipa.log"

# ============================ 语义化输出 ============================
_color() { local c="$1"; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
info()    { _color "34" "ℹ️  $*"; }
ok()      { _color "32" "✅ $*"; }
warn()    { _color "33" "⚠️  $*"; }
err()     { _color "31" "❌ $*"; }
logf()    { printf "%s %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# ============================ 自述与帮助 ============================
show_intro() {
  cat <<'EOF'
📦==================================================
                iOS IPA 打包助手
==================================================
• 自动从 DerivedData 中查找最新 .app（真机构建产物）
• 组装并导出为 .ipa 到指定目录（默认桌面）
• 可显式指定工程路径（.xcodeproj / .xcworkspace）
• 支持交互确认模式（--confirm）

提示：
  如未找到 .app，请先在 Xcode 执行一次真机构建 (Product > Build)。
==================================================
EOF
}

usage() {
  cat <<EOF
用法:
  $(basename "$0") [--config Debug|Release] [--out 输出目录] [--project 路径] [--confirm]

参数:
  --config   构建配置，默认 Release
  --out      .ipa 输出目录，默认 \$HOME/Desktop
  --project  指定 .xcodeproj 或 .xcworkspace 的完整路径
  --confirm  运行前交互确认（终端友好；SourceTree 里不要加）

示例:
  $(basename "$0") --config Release --out ~/Desktop
  $(basename "$0") --project ./MyApp.xcodeproj
EOF
}

# ============================ 参数解析 ============================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)  CONFIG="${2:-Release}"; shift 2 ;;
      --out)     OUT_DIR="${2:-$OUT_DIR}"; shift 2 ;;
      --project) PROJECT_PATH="${2:-}"; shift 2 ;;
      --confirm) CONFIRM="1"; shift ;;
      -h|--help) usage; exit 0 ;;
      *)         warn "忽略未知参数：$1"; shift ;;
    esac
  done
}

# ============================ 准备环境 ============================
prepare() {
  mkdir -p "$OUT_DIR"
  : > "$LOG_FILE"
}

# ============================ 定位仓库根 ============================
find_repo_root() {
  local root
  if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
    root="$(git rev-parse --show-toplevel)"
  else
    root="$(cd "$(dirname "$0")" && pwd)"
  fi
  echo "$root"
}

# ============================ 选工程文件 ============================
choose_project_path() {
  local root="$1"
  local path="$PROJECT_PATH"

  if [[ -z "$path" ]]; then
    set +e
    # 优先 workspace
    local WORKSPACES=($(find "$root" -maxdepth 2 -name "*.xcworkspace" -print 2>/dev/null))
    local PROJECTS=($(find "$root" -maxdepth 2 -name "*.xcodeproj"   -print 2>/dev/null))
    set -e
    if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
      path="${WORKSPACES[1]}"
    elif [[ ${#PROJECTS[@]} -gt 0 ]]; then
      path="${PROJECTS[1]}"
    else
      err "未在 $root 找到 .xcworkspace / .xcodeproj"
      exit 1
    fi
  fi

  [[ -e "$path" ]] || { err "--project 指定的路径不存在：$path"; exit 1; }
  echo "$path"
}

# ============================ 交互确认（可选） ============================
maybe_confirm() {
  local project="$1"
  if [[ "$CONFIRM" == "1" ]]; then
    echo ""
    info "🛠️ 功能：自动打包最新 .app 为 .ipa"
    info "🔧 配置：CONFIG=$CONFIG  输出目录=$OUT_DIR"
    info "📁 工程：$(basename "$project")"
    read -r "?👉 按回车继续，Ctrl+C 取消..."
  fi
}

# ============================ 寻找最新 .app ============================
find_latest_app() {
  local derived="${HOME}/Library/Developer/Xcode/DerivedData"
  [[ -d "$derived" ]] || { err "未找到 DerivedData：$derived。请先在 Xcode 完成一次真机构建。"; exit 1; }

  set +e
  local app_path
  app_path=$(ls -td "${derived}"/*/Build/Products/"${CONFIG}"-iphoneos/*.app 2>/dev/null | head -n 1)
  set -e

  if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
    warn "未在 ${derived}/**/Build/Products/${CONFIG}-iphoneos/ 找到 .app。尝试使用 Debug..."
    set +e
    app_path=$(ls -td "${derived}"/*/Build/Products/Debug-iphoneos/*.app 2>/dev/null | head -n 1)
    set -e
  fi

  [[ -n "${app_path:-}" && -d "$app_path" ]] || { err "还是找不到 .app。请确认你已用 Xcode 对真机目标完成构建（Product > Build）。"; exit 1; }
  echo "$app_path"
}

# ============================ 读取 IPA 名称 ============================
infer_ipa_name() {
  local app_dir="$1"
  local fallback="$2"
  local plist="$app_dir/Info.plist"
  local name=""
  if [[ -f "$plist" ]]; then
    name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null || true)
    [[ -z "$name" ]] && name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null || true)
  fi
  [[ -n "$name" ]] || name="$fallback"
  echo "$name"
}

# ============================ 组装 IPA ============================
package_ipa() {
  local app_dir="$1"
  local ipa_path="$2"

  local tmp_dir payload_dir
  tmp_dir="$(mktemp -d)"
  payload_dir="${tmp_dir}/Payload"

  mkdir -p "$payload_dir"
  cp -R "$app_dir" "$payload_dir/"

  info "📦 正在打包为 .ipa ..."
  (
    cd "$tmp_dir"
    /usr/bin/zip -qry "$ipa_path" "Payload"
  )
  rm -rf "$tmp_dir"
}

# ============================ 主流程 ============================
main() {
  show_intro
  parse_args "$@"
  prepare

  local repo_root project_path project_base latest_app ipa_name ipa_path
  repo_root="$(find_repo_root)"
  info "📂 工作目录：$repo_root"; logf "repo_root=$repo_root"

  project_path="$(choose_project_path "$repo_root")"
  project_base="$(basename "$project_path")"
  ok "发现工程：$project_base"; logf "project=$project_path"

  maybe_confirm "$project_path"

  latest_app="$(find_latest_app)"
  ok "最新 .app：$latest_app"; logf "app=$latest_app"

  ipa_name="$(infer_ipa_name "$latest_app" "${project_base%.*}")"
  ipa_path="${OUT_DIR}/${ipa_name}.ipa"

  package_ipa "$latest_app" "$ipa_path"
  ok "🎉 打包完成：$ipa_path"; logf "ipa=$ipa_path"

  open -R "$ipa_path" 2>/dev/null || true
}

# ============================ 执行入口 ============================
main "$@"
