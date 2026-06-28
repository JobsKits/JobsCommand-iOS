#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🫘JobsPublishPods.command
# - 核心用途：执行“🫘JobsPublishPods”对应的移动端项目自动化任务。
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
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】🫘JobsPublishPods.command'
  print -r -- '核心用途：执行“🫘JobsPublishPods”对应的移动端项目自动化任务。'
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ================================== 路径 & 日志 ==================================
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
  SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
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
  # 封装 init_log 对应的独立处理逻辑。
  init_log() {
    : > "$LOG_FILE"  # 清空旧日志
  }
  # ================================== 自述 & 确认 ==================================
  show_intro_and_wait() {
    bold_echo "========== CocoaPods 发布辅助脚本 (${SCRIPT_BASENAME}) =========="
    gray_echo "脚本路径: $SCRIPT_PATH"
    gray_echo "日志文件: $LOG_FILE"
    echo

    note_echo "本脚本将执行以下步骤："
    note_echo "1) 自检 Homebrew，如无则安装；可选更新。"
    note_echo "2) 通过 Homebrew 安装/升级 fzf。"
    note_echo "3) 在脚本当前目录查找 *.podspec，多文件时用 fzf 选择；没有就循环让你输入路径。"
    note_echo "4) 如果检测到 Git 仓库且当前 HEAD 有 tag，则把该 tag 写入 podspec 的 version 字段。"
    note_echo "5) 解析选中的 podspec，读取 name 和 version，仅作为信息展示。"
    note_echo "6) 执行 pod lib lint --allow-warnings，仅 lint 通过才继续（可选）。"
    note_echo "7) 检测是否已经登录 CocoaPods trunk："
    note_echo "   - 已登录：跳过 pod trunk register，不再询问。"
    note_echo "   - 未登录：只在首次时询问是否执行 pod trunk register。"
    note_echo "8) 执行 pod trunk push <podspec> --allow-warnings，把 Pod 推到 trunk。"
    note_echo "9) 最后执行 pod trunk info <name> 查看远端信息。"
    echo
    warm_echo "建议先确认："
    warm_echo "1) 当前 git 分支正确，代码已提交。"
    warm_echo "2) 如需用 Git tag 控制版本号，HEAD 已打好 tag。"
    warm_echo "3) 若之前从未注册过 trunk，本次可能需要进行一次 pod trunk register。"
    echo

    read -r -p "按 [Enter] 继续执行，或按 Ctrl+C 终止脚本... " _
    echo
  }
  # ================================== 工具函数 ==================================
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
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
  # 检查当前运行条件是否满足后续流程要求。
  ensure_command() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" &>/dev/null; then
      error_echo "未检测到命令: $cmd"
      [[ -n "$hint" ]] && note_echo "$hint"
      exit 1
    fi
  }
  # ================================== Homebrew & fzf ==================================
  install_homebrew() {
    local arch="$(get_cpu_arch)"
    local shell_name="${SHELL##*/}"
    local profile_file=""
    local brew_bin=""

    if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
      warn_echo "未检测到 Homebrew，准备安装（架构：$arch）"
      if [[ "$arch" == "arm64" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
        brew_bin="/opt/homebrew/bin/brew"
      else
        arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
        brew_bin="/usr/local/bin/brew"
      fi
      success_echo "Homebrew 安装完成"
    else
      command -v brew >/dev/null 2>&1 && brew_bin="$(command -v brew)"
      [[ -z "$brew_bin" && -x "/opt/homebrew/bin/brew" ]] && brew_bin="/opt/homebrew/bin/brew"
      [[ -z "$brew_bin" && -x "/usr/local/bin/brew" ]] && brew_bin="/usr/local/bin/brew"
    fi

    case "$shell_name" in
      zsh) profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *) profile_file="$HOME/.profile" ;;
    esac
    inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
    eval "$(${brew_bin} shellenv)" || true

    info_echo "Homebrew 已安装。"
    if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
      brew update  || { error_echo "brew update 失败"; return 1; }
      brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
      brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
      brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
      brew -v      || warn_echo "打印 brew 版本失败，可忽略"
      success_echo "Homebrew 健康更新完成"
    else
      note_echo "已跳过 Homebrew 更新"
    fi
  }
  # 执行对应的环境配置或同步处理。
  install_fzf() {
    if ! command -v fzf &>/dev/null; then
      note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
      brew install fzf || { error_echo "❌ fzf 安装失败"; exit 1; }
      success_echo "✅ fzf 安装成功"
    else
      info_echo "🔄 fzf 已安装。是否执行升级？"
      echo "👉 直接按 [Enter]：跳过升级"
      echo "👉 输入任意字符后回车：执行升级（brew upgrade fzf && brew cleanup）"

      local confirm
      IFS= read -r confirm
      if [[ -n "$confirm" ]]; then
        info_echo "⏳ 正在升级 fzf..."
        brew upgrade fzf       || { error_echo "❌ fzf 升级失败"; return 1; }
        brew cleanup           || { warn_echo  "⚠️  brew cleanup 执行时有警告"; }
        success_echo "✅ fzf 已升级到最新版本"
      else
        note_echo "⏭️ 已选择跳过 fzf 升级"
      fi
    fi
  }

  # ================================== Podspec 选择 ==================================
  PODSPEC_PATH=""
  PODSPEC_BASENAME=""
  POD_NAME=""
  POD_VERSION=""
  GIT_TAG=""
  # 收集并校验用户输入，决定后续执行路径。
  select_podspec_in_script_dir() {
    local search_dir="$SCRIPT_DIR"
    local podspec_files=("$search_dir"/*.podspec)

    if [[ ! -e "${podspec_files[0]}" ]]; then
      warn_echo "在脚本目录($search_dir)下未找到任何 *.podspec 文件。"
      ask_podspec_from_user
      return
    fi

    if [[ ${#podspec_files[@]} -eq 1 ]]; then
      PODSPEC_PATH="${podspec_files[0]}"
      PODSPEC_BASENAME="$(basename "$PODSPEC_PATH")"
      success_echo "自动选中 podspec: $PODSPEC_BASENAME"
      return
    fi

    # 多个 podspec，用 fzf 选择
    ensure_command fzf "请先安装 fzf（brew install fzf）"
    note_echo "检测到多个 podspec，请选择要发布的那个："

    local selected_basename
    selected_basename=$(printf '%s\n' "${podspec_files[@]##"$search_dir"/}" | \
      fzf --prompt="选择 podspec: " --height=40%) || {
      error_echo "未选择任何 podspec，发布流程中断。"
      exit 1
    }

    PODSPEC_PATH="$search_dir/$selected_basename"
    PODSPEC_BASENAME="$selected_basename"
    success_echo "已选择 podspec: $PODSPEC_BASENAME"
  }
  # 收集并校验用户输入，决定后续执行路径。
  ask_podspec_from_user() {
    while :; do
      warm_echo "请手动输入要发布的 .podspec 文件路径（可直接将文件拖入终端后回车）："
      printf "> "
      local input
      IFS= read -r input

      # 处理拖入路径时自动加的引号
      input="${input%\"}"; input="${input#\"}"
      input="${input%\'}"; input="${input#\'}"

      # 处理 ~
      input=${input/#~/$HOME}

      if [[ -f "$input" ]]; then
        PODSPEC_PATH="$input"
        PODSPEC_BASENAME="$(basename "$PODSPEC_PATH")"
        success_echo "已选择 podspec: $PODSPEC_BASENAME"
        break
      else
        error_echo "路径无效或文件不存在: $input"
      fi
    done
  }
  # ================================== Git tag → version 同步 ==================================
  find_git_repo_root() {
    # 从脚本目录往上找 .git
    local dir="$SCRIPT_DIR"
    while [[ "$dir" != "/" && ! -d "$dir/.git" ]]; do
      dir="$(dirname "$dir")"
    done
    if [[ -d "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    return 1
  }
  # 执行对应的环境配置或同步处理。
  sync_podspec_version_with_git_tag_if_possible() {
    local repo_root
    if ! repo_root=$(find_git_repo_root); then
      debug_echo "未检测到 .git 目录，跳过 Git tag → version 同步。"
      return
    fi

    if ! command -v git &>/dev/null; then
      warn_echo "检测到 .git，但系统未安装 git，无法同步 version。"
      return
    fi

    info_echo "检测到 Git 仓库: $repo_root"

    # 只取“当前 HEAD 上的 tag”
    local tags
    tags=$(cd "$repo_root" && git tag --points-at HEAD)
    if [[ -z "$tags" ]]; then
      warn_echo "当前 HEAD 没有打 tag，保持 podspec 中原有 version，不做自动覆盖。"
      return
    fi

    local tag
    tag=$(printf '%s\n' "$tags" | head -n1)
    GIT_TAG="$tag"
    highlight_echo "使用 Git tag 作为版本号: $GIT_TAG"
    ensure_command ruby "需要 Ruby 来修改 podspec 中 version 字段。"

    local spec_file="$PODSPEC_PATH"
    local ruby_script
    ruby_script=$(cat << 'RUBY'
  spec_path = ARGV[0]
  new_version = ARGV[1]
  content = File.read(spec_path)
  pattern = /(\.version\s*=\s*['"])[^'"]+(['"])/
  unless content =~ pattern
    STDERR.puts "未在 podspec 中找到 version 字段。"
    exit 1
  end
  content.sub!(pattern) { "#{$1}#{new_version}#{$2}" }
  File.write(spec_path, content)
RUBY
    )

    if ruby -e "$ruby_script" "$spec_file" "$GIT_TAG" 2>/tmp/podspec_version_update_error.log; then
      success_echo "已将 podspec 中的 version 更新为 Git tag: $GIT_TAG"
    else
      warn_echo "尝试用 Git tag 更新 version 失败，详情见 /tmp/podspec_version_update_error.log；将使用原始 version。"
    fi
  }
  # ================================== Podspec 解析 ==================================
  read_podspec_metadata() {
    ensure_command ruby "CocoaPods 依赖 Ruby，请先安装 Ruby 环境。"

    local spec_file="$PODSPEC_PATH"
    if [[ ! -f "$spec_file" ]]; then
      error_echo "podspec 文件不存在: $spec_file"
      exit 1
    fi

    local ruby_script
    ruby_script=$(cat << 'RUBY'
  require 'cocoapods'
  spec_path = ARGV[0]
  spec = Pod::Specification.from_file(spec_path)
  puts spec.name
  puts spec.version
RUBY
    )

    local output
    if ! output=$(ruby -e "$ruby_script" "$spec_file" 2>/tmp/podspec_parse_error.log); then
      error_echo "使用 Ruby 解析 podspec 失败，详情见 /tmp/podspec_parse_error.log"
      exit 1
    fi

    POD_NAME=$(echo "$output" | sed -n '1p')
    POD_VERSION=$(echo "$output" | sed -n '2p')

    if [[ -z "$POD_NAME" || -z "$POD_VERSION" ]]; then
      error_echo "未能从 podspec 中解析出 name/version，请检查文件。"
      exit 1
    fi

    info_echo "📦 Pod 名称: $POD_NAME"
    info_echo "🏷 版本号: $POD_VERSION"
  }
  # ================================== CocoaPods trunk 相关 ==================================
  ensure_cocoapods() {
    ensure_command pod "请先安装 CocoaPods，例如: sudo gem install cocoapods"
  }
  # 检查当前运行条件是否满足后续流程要求。
  is_trunk_logged_in() {
    # 使用 pod trunk me 判断是否已经登录；只要成功就认为“注册+登录过”
    local tmp_log="/tmp/pod_trunk_me_${SCRIPT_BASENAME}.log"
    if pod trunk me >"$tmp_log" 2>&1; then
      local name email
      name=$(grep -E '^\s*Name:'  "$tmp_log" | sed 's/^[[:space:]]*Name:[[:space:]]*//')
      email=$(grep -E '^\s*Email:' "$tmp_log" | sed 's/^[[:space:]]*Email:[[:space:]]*//')
      if [[ -n "$name" || -n "$email" ]]; then
        info_echo "当前已登录 CocoaPods trunk: ${name:-?} <${email:-?}>"
      else
        info_echo "当前已登录 CocoaPods trunk。"
      fi
      return 0
    fi
    debug_echo "pod trunk me 失败，推测当前环境尚未登录 trunk。"
    return 1
  }
  # 封装 maybe_trunk_register 对应的独立处理逻辑。
  maybe_trunk_register() {
    # 如果已经登录过 trunk，就完全跳过，不再问
    if is_trunk_logged_in; then
      note_echo "检测到已登录 CocoaPods trunk，跳过 pod trunk register 步骤。"
      return
    fi

    warm_echo "当前环境尚未登录 CocoaPods trunk（pod trunk me 失败）。"
    warm_echo "通常只在首次使用该邮箱时需要执行 pod trunk register。"
    echo "是否现在执行 pod trunk register? [y/N]"
    printf "> "
    local ans
    IFS= read -r ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      note_echo "已选择跳过 pod trunk register（若从未注册过，该环境可能无法成功 pod trunk push）。"
      return
    fi

    local email
    while :; do
      warm_echo "请输入用于 CocoaPods trunk 的注册邮箱："
      printf "> "
      IFS= read -r email
      if [[ -n "$email" ]]; then
        break
      fi
      warn_echo "邮箱不能为空。"
    done

    info_echo "执行: pod trunk register $email 'Jobs' --description='$PODSPEC_BASENAME'"
    if pod trunk register "$email" 'Jobs' --description="$PODSPEC_BASENAME"; then
      success_echo "已发起 trunk 注册请求。"
      note_echo "请前往邮箱查收 CocoaPods 发来的确认邮件并完成验证后再继续发布。"
    else
      error_echo "pod trunk register 执行失败，你可以手动检查原因或稍后重试。"
    fi
  }
  # ================================== CocoaPods 发布 ==================================
  run_pod_lib_lint() {
    info_echo "开始执行 pod lib lint --allow-warnings $PODSPEC_BASENAME"
    if pod lib lint --allow-warnings "$PODSPEC_PATH"; then
      success_echo "✅ pod lib lint 校验通过"
    else
      error_echo "❌ pod lib lint 校验失败，发布流程终止。"
      exit 1
    fi
  }
  # 封装 maybe_run_pod_lib_lint 对应的独立处理逻辑。
  maybe_run_pod_lib_lint() {
    warm_echo "是否先执行 pod lib lint --allow-warnings？"
    echo "👉 直接按 [Enter]：先执行 pod lib lint（推荐，确保本地能通过）"
    echo "👉 输入任意内容后回车：跳过 lint，直接进行 trunk 发布流程（风险自负）"
    printf "> "
    local ans
    IFS= read -r ans
    echo

    if [[ -z "$ans" ]]; then
      note_echo "将先执行 pod lib lint ..."
      run_pod_lib_lint
    else
      warn_echo "已选择跳过 pod lib lint，脚本将直接进入 trunk 发布流程。"
    fi
  }
  # 封装 push_to_trunk 对应的独立处理逻辑。
  push_to_trunk() {
    info_echo "准备执行 pod trunk push $PODSPEC_BASENAME --allow-warnings"
    warm_echo "确保该 Pod 已完成 trunk 邮箱验证，并且本地 'pod trunk me' 状态正常。"
    echo "按 [Enter] 继续推送，或 Ctrl+C 取消。"
    IFS= read -r _

    local tmp_log="/tmp/pod_trunk_push_${SCRIPT_BASENAME}.log"
    info_echo "pod trunk push 输出已同步记录到: $tmp_log"

    # 执行 push，并通过 tee 显示 + 记录日志
    pod trunk push "$PODSPEC_PATH" --allow-warnings 2>&1 | tee "$tmp_log"
    local exit_code=${PIPESTATUS[0]}   # 取 pipeline 中第一个命令（pod）的退出码

    if [[ $exit_code -eq 0 ]]; then
      success_echo "✅ pod trunk push 成功 ($POD_NAME $POD_VERSION)"
      return 0
    fi

    # ---- 失败情况：先判断是不是 CocoaPods 的内部错误 ----
    if grep -q "An internal server error occurred" "$tmp_log"; then
      warn_echo "⚠ 检测到 CocoaPods Trunk 返回 Internal Server Error（服务器内部错误）。"
      note_echo "大概率是 CocoaPods 官方服务故障，并不一定是你的 podspec 有问题。"
      echo
      warm_echo "按 [Enter] 继续执行后续步骤（本次 push 失败，但脚本不会中断）；"
      warm_echo "或者输入任意字符后回车：立刻结束脚本。"
      printf "> "
      local ans
      IFS= read -r ans
      if [[ -z "$ans" ]]; then
        note_echo "已选择继续：脚本将跳过本次 push 错误，继续执行后续步骤。"
        return 0
      else
        error_echo "已根据你的选择终止脚本。"
        exit 1
      fi
    fi

    # ---- 其它错误：仍然直接终止 ----
    error_echo "❌ pod trunk push 失败，请检查上面的错误信息（非服务器内部错误）。"
    exit 1
  }
  # 封装 show_trunk_info 对应的独立处理逻辑。
  show_trunk_info() {
    info_echo "查询 trunk 上的 Pod 信息: $POD_NAME"
    if pod trunk info "$POD_NAME"; then
      success_echo "已展示 pod trunk info $POD_NAME"
    else
      warn_echo "pod trunk info 查询失败，请确认该 Pod 是否已成功发布。"
    fi
  }
  # ================================== main ==================================
  main() {
    init_log
    show_intro_and_wait

    # 1. 自检 / 安装 Homebrew + fzf
    install_homebrew
    install_fzf
    ensure_cocoapods

    # 2. 选择 podspec
    select_podspec_in_script_dir

    # 3. 如果有 Git 仓库 & HEAD 有 tag，用 tag 覆盖 podspec 的 version
    sync_podspec_version_with_git_tag_if_possible

    # 4. 解析 name / version
    read_podspec_metadata

    # 5. 是否执行 lint（回车跳过，输入任意字符执行，否则直接跳过）
    maybe_run_pod_lib_lint

    # 6. trunk register（仅在当前环境未登录 trunk 时，才问一次）
    maybe_trunk_register

    # 7. push & 查看 info
    push_to_trunk
    show_trunk_info

    success_echo "🎉 发布流程结束。"
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
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
