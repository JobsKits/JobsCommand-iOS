#!/bin/zsh
# ===============================================================
#  clean_ios_like.command
# ---------------------------------------------------------------
#  功能：
#   • 在项目根目录执行，自动识别 Flutter iOS 或纯 iOS 工程
#   • 执行常见缓存清理（Pods、DerivedData、Flutter 构建产物等）
#   • 结构化封装：所有逻辑函数化，main 中统一调用
#   • 执行前显示自述，并等待用户回车确认；提供 --yes 跳过确认
# ---------------------------------------------------------------
#  用法：
#   • 将脚本放到项目根目录（与 .git 同级），双击或终端执行：
#     ./clean_ios_like.command            # 正常模式（交互确认）
#     ./clean_ios_like.command --yes      # 非交互模式（直接执行）
# ===============================================================

set -u  # 禁止未定义变量；不使用 -e，避免单点失败直接中断

# =========================== 输出方法 ===========================
info()    { echo "📘 $1"; }
success() { echo "✅ $1"; }
error()   { echo "❌ $1"; }

# =========================== 自述页面 ===========================
show_intro() {
  clear
  cat <<'EOF'
🧹=================================================
              iOS / Flutter iOS 清理工具
=================================================
将清理以下内容（按项目类型自动识别）：

【iOS 工程】
  • Pods/
  • Podfile.lock
  • Xcode DerivedData（当前用户下）

【Flutter iOS 工程】
  • ios/Pods
  • ios/Podfile.lock
  • ios/.symlinks
  • ios/Flutter 目录下缓存（App.framework、*.xcframework 等）
  • .dart_tool、build、pubspec.lock
  • Xcode DerivedData（当前用户下）

⚠️ 注意：该操作会删除本地缓存与构建产物，请确保已保存修改。
=================================================
EOF
}

wait_for_enter() {
  read "?👉 按回车键确认继续（或 Ctrl+C 取消）..."
}

# =========================== 目录与参数 ===========================
enter_script_dir() {
  # 强制切到脚本所在目录（项目根）
  local base_dir
  base_dir="$(cd "$(dirname "$0")" && pwd)"
  cd "$base_dir" || { error "无法进入脚本目录：$base_dir"; exit 1; }
  info "📂 当前起点: $base_dir"
}

parse_args() {
  # 支持 --yes 跳过确认
  SKIP_CONFIRM="0"
  for arg in "$@"; do
    case "$arg" in
      --yes|-y) SKIP_CONFIRM="1" ;;
    esac
  done
}

confirm_or_exit() {
  [[ "$SKIP_CONFIRM" == "1" ]] && return 0
  echo
  read "?⚠️  确认执行清理吗？(y/N): " yn
  case "${yn:l}" in
    y|yes) return 0 ;;
    *) info "已取消。"; exit 0 ;;
  esac
}

# =========================== 清理实现 ===========================
clean_ios() {
  local path="$1"
  cd "$path" || { error "无法进入 $path"; exit 1; }

  info "🧹 正在清理 iOS 缓存目录..."
  rm -rf Pods
  rm -rf Podfile.lock
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
  success "🧽 iOS 缓存清理完成"
}

clean_flutter_ios() {
  local path="$1"
  cd "$path" || { error "无法进入 $path"; exit 1; }

  info "🧹 正在清理 Flutter iOS 缓存..."
  rm -rf ios/Pods
  rm -rf ios/Podfile.lock
  rm -rf ios/.symlinks
  rm -rf ios/Flutter/Flutter.podspec
  rm -rf ios/Flutter/App.framework
  rm -rf ios/Flutter/engine
  rm -rf ios/Flutter/*.xcframework
  rm -rf ios/Flutter/Flutter.framework
  rm -rf ios/Flutter/flutter_export_environment.sh
  rm -rf ios/Flutter/Generated.xcconfig
  rm -rf ios/Flutter/ephemeral
  rm -rf .dart_tool
  rm -rf build
  rm -rf pubspec.lock
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
  success "🧽 Flutter iOS 缓存清理完成"
}

# =========================== 类型识别 ===========================
detect_project_type() {
  # 返回：echo "flutter" | "ios" | "unknown"
  if [[ -f "pubspec.yaml" && -d "ios" ]]; then
    echo "flutter"
  elif [[ -f "Podfile" ]]; then
    echo "ios"
  else
    echo "unknown"
  fi
}

# =========================== 主函数 ===========================
main() {
  parse_args "$@"
  show_intro
  wait_for_enter
  enter_script_dir
  confirm_or_exit

  local kind
  kind="$(detect_project_type)"

  case "$kind" in
    flutter)
      info "🧩 检测到 Flutter 工程"
      clean_flutter_ios "$(pwd)"
      ;;
    ios)
      info "📱 检测到 iOS 工程"
      clean_ios "$(pwd)"
      ;;
    *)
      error "无法识别的工程结构，未检测到 Podfile 或 pubspec.yaml"
      exit 1
      ;;
  esac

  success "🎉 全部完成"
}

# =========================== 执行入口 ===========================
main "$@"
