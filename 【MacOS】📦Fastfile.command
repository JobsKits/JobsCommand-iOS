#!/bin/zsh
# ===============================================================
#  Jobs Fastlane 初始化脚本（macOS / zsh）
# ---------------------------------------------------------------
#  功能：
#   • 识别 Flutter 工程或原生 iOS 工程
#   • 安装/更新 Homebrew、fzf、fastlane
#   • 创建并用所选编辑器打开 Fastfile
#  交互：
#   • 启动显示自述，回车确认后继续
#   • 选择是否创建 Fastfile、选择打开的编辑器
# ---------------------------------------------------------------
#  用法：
#    chmod +x jobs_fastlane_bootstrap.command
#    ./jobs_fastlane_bootstrap.command
# ===============================================================

set -u  # 禁止未定义变量；不启用 -e，关键步骤自行判错

########## ✅ 彩色输出 ##########
_JobsPrint()         { echo "$1$2\033[0m"; }
_JobsPrint_Green()   { _JobsPrint "\033[1;32m" "$1"; }
_JobsPrint_Red()     { _JobsPrint "\033[1;31m" "$1"; }
_JobsPrint_Yellow()  { _JobsPrint "\033[1;33m" "$1"; }
_JobsPrint_Blue()    { _JobsPrint "\033[1;34m" "$1"; }

########## ✅ 自述 ##########
show_intro() {
  _JobsPrint_Green "🧮 Fastlane 自动配置初始化脚本"
  _JobsPrint_Green "📦 脚本用途："
  _JobsPrint_Green "1️⃣ 自动识别当前是 Flutter 工程还是原生 iOS 工程"
  _JobsPrint_Green "2️⃣ 安装或更新 Homebrew、fzf、fastlane"
  _JobsPrint_Green "3️⃣ 创建并打开 Fastfile 以开始配置自动化流程"
  echo ""
  read "?👉 按下回车键继续执行（Ctrl+C 取消）..."
}

########## ✅ 路径设置 ##########
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
FASTFILE_PATH="$SCRIPT_DIR/fastlane/Fastfile"
PROJECT_TYPE="unknown"

########## ✅ LOGO（可选） ##########
jobs_logo() {
  _JobsPrint_Green "======== Jobs Fastlane 初始化脚本 ========"
}

########## ✅ 检测工程类型 ##########
detect_project_type() {
  if [[ -f "$SCRIPT_DIR/pubspec.yaml" && -d "$SCRIPT_DIR/ios" ]]; then
    PROJECT_TYPE="flutter"
    _JobsPrint_Green "🧩 检测到 Flutter 工程"
  elif ls "$SCRIPT_DIR"/*.xcodeproj >/dev/null 2>&1 || ls "$SCRIPT_DIR"/*.xcworkspace >/dev/null 2>&1; then
    PROJECT_TYPE="ios"
    _JobsPrint_Green "📱 检测到原生 iOS 工程"
  else
    PROJECT_TYPE="unknown"
    _JobsPrint_Red "⚠️ 无法识别工程类型（Flutter 或 iOS）"
  fi
}

########## ✅ 写 Homebrew 路径到 Shell Profile ##########
_configure_brew_path() {
  # 兼容 Intel 与 Apple Silicon
  local brew_bins=(
    "/opt/homebrew/bin"   # Apple Silicon 默认
    "/usr/local/bin"      # Intel 常见
  )
  local path_line_prefix='export PATH="'
  local updated=0
  for b in "${brew_bins[@]}"; do
    if [[ -d "$b" ]]; then
      local line="export PATH=\"$b:\$PATH\""
      for f in ".zshrc" ".bash_profile" ".bashrc"; do
        if [[ -f "$HOME/$f" ]]; then
          grep -qF "$line" "$HOME/$f" 2>/dev/null || { echo "$line" >> "$HOME/$f"; updated=1; }
        else
          echo "$line" >> "$HOME/$f"; updated=1
        fi
      done
    fi
  done
  # 尝试加载
  source "$HOME/.zshrc" 2>/dev/null || true
  source "$HOME/.bashrc" 2>/dev/null || true
  source "$HOME/.bash_profile" 2>/dev/null || true
  (( updated )) && _JobsPrint_Yellow "ℹ️ 已写入 Homebrew PATH 到 shell 配置文件"
}

########## ✅ 安装 Homebrew ##########
install_homebrew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    _JobsPrint_Red "❌ Homebrew 安装失败"; return 1;
  }
  _configure_brew_path
  return 0
}

check_homebrew() {
  if ! command -v brew &>/dev/null; then
    _JobsPrint_Yellow "🍺 未检测到 Homebrew，开始安装..."
    install_homebrew || return 1
  else
    _JobsPrint_Green "✅ Homebrew 已安装"
    brew update || true
    brew upgrade || true
    brew cleanup || true
  fi
  return 0
}

########## ✅ 安装 fzf ##########
install_fzf() {
  _JobsPrint_Yellow "🔧 安装 fzf..."
  brew install fzf || return 1
  # 安装交互按键绑定脚本（静默）
  if [[ -x "/opt/homebrew/opt/fzf/install" ]]; then
    /opt/homebrew/opt/fzf/install --key-bindings --completion --no-bash --no-fish --no-update-rc >/dev/null 2>&1 || true
  elif [[ -x "$HOME/.fzf/install" ]]; then
    "$HOME/.fzf/install" --key-bindings --completion --no-bash --no-fish --no-update-rc >/dev/null 2>&1 || true
  fi
  _JobsPrint_Green "✅ fzf 安装完成"
  return 0
}

check_fzf() {
  if ! command -v fzf &>/dev/null; then
    install_fzf || _JobsPrint_Red "⚠️ fzf 安装失败，稍后编辑器选择将使用降级逻辑"
  else
    _JobsPrint_Green "✅ fzf 已安装"
    brew upgrade fzf || true
  fi
}

########## ✅ 安装 fastlane ##########
install_fastlane() {
  _JobsPrint_Yellow "🚀 安装 fastlane..."
  brew install fastlane || return 1
  _JobsPrint_Green "✅ fastlane 安装成功"
  return 0
}

check_fastlane() {
  if ! command -v fastlane &>/dev/null; then
    install_fastlane || _JobsPrint_Red "⚠️ fastlane 安装失败，请手动检查环境"
  else
    _JobsPrint_Green "✅ fastlane 已安装"
    brew upgrade fastlane || true
  fi
}

########## ✅ 选择编辑器并打开 Fastfile ##########
_select_editor_and_open() {
  local target="$1"

  # 候选编辑器与可执行命令的映射
  local options=("Xcode" "VSCode" "Android Studio")
  local selection=""

  if command -v fzf >/dev/null 2>&1; then
    selection=$(printf "%s\n" "${options[@]}" | fzf --prompt="🎨 选择编辑器: " --height=10 --reverse) || selection=""
  fi

  # fzf 不可用或用户取消 → 交互降级
  if [[ -z "$selection" ]]; then
    _JobsPrint_Yellow "⚠️ 未选择或缺少 fzf，将尝试使用可用编辑器打开（优先级：VSCode > Xcode > Android Studio）"
    if command -v code >/dev/null 2>&1; then
      selection="VSCode"
    elif open -Ra "Xcode" >/dev/null 2>&1; then
      selection="Xcode"
    elif open -Ra "Android Studio" >/dev/null 2>&1; then
      selection="Android Studio"
    else
      _JobsPrint_Red "❌ 未找到可用编辑器，跳过打开。"
      return 0
    fi
  fi

  case "$selection" in
    "Xcode")           open -a "Xcode" "$target" ;;
    "VSCode")          command -v code >/dev/null 2>&1 && code "$target" || open -a "Visual Studio Code" "$target" ;;
    "Android Studio")  open -a "Android Studio" "$target" ;;
    *)                 _JobsPrint_Yellow "⚠️ 未识别的选择，跳过打开" ;;
  esac
}

open_fastfile() {
  mkdir -p "$SCRIPT_DIR/fastlane"

  if [[ ! -f "$FASTFILE_PATH" ]]; then
    _JobsPrint_Yellow "📄 未检测到 Fastfile，是否要创建？"
    read "?👉 输入 y 创建，其他键跳过： " init_ans
    if [[ "$init_ans" == "y" ]]; then
      cat > "$FASTFILE_PATH" <<'RUBY'
# Fastfile initialized by Jobs script
default_platform(:ios)

platform :ios do
  desc "Build for beta"
  lane :beta do
    # build_app(scheme: "YourScheme")
  end
end
RUBY
      _JobsPrint_Green "✅ Fastfile 创建成功: $FASTFILE_PATH"
    fi
  fi

  if [[ -f "$FASTFILE_PATH" ]]; then
    _JobsPrint_Green "🧠 请选择用哪个编辑器打开 Fastfile："
    _select_editor_and_open "$FASTFILE_PATH"
  fi
}

########## ✅ main（统一调用） ##########
main() {
  cd "$SCRIPT_DIR" || { _JobsPrint_Red "❌ 无法进入脚本目录"; exit 1; }

  show_intro
  jobs_logo
  detect_project_type

  # 基础环境
  check_homebrew || { _JobsPrint_Red "❌ Homebrew 安装/检测失败"; exit 1; }
  check_fzf
  check_fastlane

  open_fastfile

  _JobsPrint_Green "🎉 完成"
}

########## ✅ 执行入口 ##########
main "$@"
