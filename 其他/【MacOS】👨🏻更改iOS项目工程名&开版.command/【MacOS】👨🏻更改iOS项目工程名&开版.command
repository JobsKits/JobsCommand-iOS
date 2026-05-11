#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}

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

ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}

confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

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

run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}

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

show_readme_and_wait() {
  clear
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

run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # 打印 "Jobs" logo
  jobs_logo() {
      local logo="
  JJJJJJJJ     oooooo    bb          SSSSSSSSSS
        JJ    oo    oo   bb          SS      SS
        JJ    oo    oo   bb          SS
        JJ    oo    oo   bbbbbbbbb   SSSSSSSSSS
  J     JJ    oo    oo   bb      bb          SS
  JJ    JJ    oo    oo   bb      bb  SS      SS
   JJJJJJ      oooooo     bbbbbbbb   SSSSSSSSSS
  "
      _JobsPrint_Green "$logo"
  }
  # 定义新的工程名变量
  NEW_PROJECT_NAME="Monkey"
  # 全局变量声明
  typeset -g CURRENT_DIRECTORY=$(dirname "$(readlink -f "$0")") # 获取当前脚本文件的目录
  typeset -g DESKTOP_PATH # 定义目标桌面路径
  typeset -g SHORTCUT_DESKTOP_PATH # 创建一份由 pod 创建的文件目录索引（*.xcworkspace）文件 替身/快捷方式/别名 到桌面
  typeset -g WORKSPACE_FILE # 原始的 *.xcworkspace 的位置
  typeset -g script_dir # /Users/user/Desktop/Monkey
  typeset -g default_old_project_name # JobsOCBaseConfig
  typeset -g script_path # 执行的脚本路径
  # 通用打印方法
  _JobsPrint() {
      local COLOR="$1"
      local text="$2"
      local RESET="\033[0m"
      echo "${COLOR}${text}${RESET}"
  }
  # 定义红色加粗输出方法
  _JobsPrint_Red() {
      _JobsPrint "\033[1;31m" "$1"
  }
  # 定义绿色加粗输出方法
  _JobsPrint_Green() {
      _JobsPrint "\033[1;32m" "$1"
  }
  # 自述信息
  self_intro() {
      _JobsPrint_Red "【MacOS】更改iOS项目工程名"
      _JobsPrint_Red "按回车键继续..."
      read
  }
  # 切换到脚本运行的当前目录
  set_and_cd_to_script_dir() {
      cd "$CURRENT_DIRECTORY" || { _JobsPrint_Red "切换目录失败"; exit 1; }
  }
  # 定义获取脚本目录的方法
  get_script_dir() {
      script_path="${(%):-%x}" # 在 zsh 中，${(%):-%x} 将展开为当前脚本的绝对路径。
      DESKTOP_PATH="$HOME/Desktop/$NEW_PROJECT_NAME" # 定义目标桌面路径
      script_dir=$DESKTOP_PATH  # 将 script_dir 设置为桌面路径
      _JobsPrint_Red "当前脚本的执行路径 = $script_path"
      _JobsPrint_Red "当前脚本的执行目录：$script_dir"
  }
  # 设置 Git 配置
  setup_git() {
      # 增加 Git 的缓冲区大小
      git config --global http.postBuffer 524288000  # 设置缓冲区为500MB
      # 将 http.maxRequestBuffer 设置为较高的值
      # 目的是允许 Git 在通过 HTTP 与远程仓库通信时处理更大的请求。
      # 这可以帮助防止例如 "RPC failed" 和 "fatal: early EOF" 这样的错误，特别是在处理大型仓库或文件时。适用于当前用户执行的所有 Git 操作。
      git config --global http.maxRequestBuffer 1048576000  # 允许 Git 在通过 HTTP 与远程仓库通信时处理更大的请求
  }
  # HomeBrew 安装或升级 jq
  # jq 是一个轻量级且灵活的命令行 JSON 处理器，它允许你对 JSON 数据进行各种操作，如解析、过滤、映射和转换结构化数据
  install_or_upgrade_jq() {
      # 检查 jq 是否已安装
      if brew list jq &>/dev/null; then
          _JobsPrint_Green "jq 已安装，检查是否有可用的升级..."
          # 检查是否存在可用的升级
          if brew outdated | grep jq &>/dev/null; then
              _JobsPrint_Green "存在可用的升级，正在升级 jq..."
              ask_run "升级 jq？" && brew upgrade jq
          else
              _JobsPrint_Green "当前 jq 已是最新版本。"
          fi
      else
          _JobsPrint_Red "jq 未安装，正在安装..."
          brew install jq
      fi
  }
  # 检查和设置镜像
  check_and_set_mirror() {
      # 获取当前公网 IP 和地理位置信息
      local IP_INFO=$(curl -s https://ipinfo.io)
      local COUNTRY=$(echo $IP_INFO | jq -r '.country')
      _JobsPrint_Green "您的 IP 地址位于: $COUNTRY"
      # 判断当前是否在中国大陆
      if [ "$COUNTRY" = "CN" ]; then
          _JobsPrint_Red "检测到您当前在中国大陆。"
          _JobsPrint_Red "请输入 '1' 切换到清华大学镜像，或直接回车使用默认镜像："
          read user_choice
          if [ "$user_choice" = "1" ]; then
              _JobsPrint_Green "将使用清华大学镜像..."
              add_line_if_not_exists "Podfile" "source 'https://mirrors.tuna.tsinghua.edu.cn/git/CocoaPods/Specs.git'"
          else
              _JobsPrint_Green "将使用默认镜像..."
          fi
      else
          _JobsPrint_Green "您不在中国大陆，将使用默认镜像。"
      fi
  }
  # 定义一个函数用于搜索和替换内容
  search_and_replace() {
      local file_path="$1"
      local search_term="$2"
      local replace_term="$3"
      get_script_dir
      if [[ ! -f $file_path ]]; then
          _JobsPrint_Red "文件不存在。"
          return 1
      fi
      if grep -q "$search_term" "$file_path"; then
          sed -i "" "s/$search_term/$replace_term/g" "$file_path"
          _JobsPrint_Green "内容已从 '$search_term' 替换为 '$replace_term'。"
      else
          _JobsPrint_Red "文件中没有找到 '$search_term'。"
      fi
  }
  # 复制文件夹，排除.git目录，到桌面，并重命名为 $NEW_PROJECT_NAME
  copy_to_desk(){
      # rsync 是一个非常流行的文件传输和同步工具，通常用于有效地复制和同步文件到本地目录或者通过网络到其他服务器。
      # 它是许多 UNIX 和类 UNIX 系统（包括 Linux 和 macOS）中的标准工具之一。
      # 在 macOS 上，rsync 通常预装在系统中。
      # 可以通过打开终端并输入 rsync --version 来检查它是否已经安装以及其版本信息
      rsync -av --exclude '.git' "$CURRENT_DIRECTORY/" "$DESKTOP_PATH/" --progress
      _JobsPrint_Green "文件夹已成功复制到桌面并重命名为 $NEW_PROJECT_NAME "
      cd "$DESKTOP_PATH" || { _JobsPrint_Red "切换目录失败"; exit 1; }
  }
  # 更新 Oh My Zsh
  update_OhMyZsh() {
      _JobsPrint_Red "检查是否有新版本..."
      cd ~/.oh-my-zsh || exit
      git fetch origin master
      if git rev-list --count HEAD..origin/master | grep -q '^0$' > /dev/null; then
          _JobsPrint_Green "已经是最新版本，无需更新。"
      else
          _JobsPrint_Red "发现新版本，正在升级 Oh My Zsh..."
          git pull origin master
      fi
  }
  # 检查并安装 Oh My Zsh
  check_OhMyZsh() {
      if [ ! -d "$HOME/.oh-my-zsh" ]; then
          _JobsPrint_Red "当前系统中未安装 Oh My Zsh，正在进行安装..."
          sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
          return 1
      else
          _JobsPrint_Red "当前系统中已安装 Oh My Zsh，进行检查更新升级。"
          update_OhMyZsh
          return 0
      fi
  }
  # 检查系统是否支持 Rosetta 2
  check_rosetta_compatibility() {
      # 检查 Rosetta 2 是否已安装
      if /usr/bin/pgrep oahd &> /dev/null; then
          _JobsPrint_Green "Rosetta 2 已安装，跳过安装。"
      else
          _JobsPrint_Red "当前系统支持 Rosetta 2，正在安装..."
          if /usr/sbin/softwareupdate --install-rosetta --agree-to-license &> /dev/null; then
              _JobsPrint_Green "Rosetta 2 安装成功"
          else
              _JobsPrint_Red "当前系统不支持 Rosetta 2 安装失败"
          fi
      fi
  }
  # 准备前置环境
  prepare_environment() {
      _JobsPrint_Green "先做一些准备工作..."
      defaults write com.apple.Finder AppleShowAllFiles YES
      sudo spctl --master-disable
      check_OhMyZsh
      check_rosetta_compatibility
    
      read "new_proj_name?请输入新工程名（按回车使用默认值: $NEW_PROJECT_NAME）："
      # 如果用户输入了新值，则更新 NEW_PROJECT_NAME
      # -z: 这个条件测试字符串是否为空。如果字符串的长度为零，则条件为真。
      # -n: 这个条件测试字符串是否非空。如果字符串的长度大于零，则条件为真。
      if [[ -n "$new_proj_name" ]]; then
          NEW_PROJECT_NAME="$new_proj_name"
      fi
      _JobsPrint_Green "新工程名为：$NEW_PROJECT_NAME"
  }
  # 检查 Xcode 和 Xcode Command Line Tools
  check_xcode_and_tools() {
      if ! command -v xcodebuild &> /dev/null; then
          _JobsPrint_Red "Xcode 未安装，请安装后再运行此脚本。"
          open -a "App Store" "macappstore://apps.apple.com/app/xcode/id497799835"
          return 1
      fi

      if ! xcode-select -p &> /dev/null; then
          _JobsPrint_Red "Xcode Command Line Tools 未安装，请安装后再运行此脚本。"
          xcode-select --install
          _JobsPrint_Red "请按照提示进行安装，安装完成后再次运行此脚本。"
          return 0
      fi
      _JobsPrint_Red "🍺🍺🍺 Xcode 和 Xcode Command Line Tools 均已安装。"
  }
  # 检查并安装/更新 fzf
  check_and_update_fzf() {
      if ! command -v fzf &> /dev/null; then
          _JobsPrint_Red "fzf 没有安装，正在安装到最新版本"
          brew install fzf
      else
          _JobsPrint_Red "fzf 已被安装，正在检查更新..."
          ask_run "升级 fzf？" && brew upgrade fzf
          outdated_packages=$(brew outdated fzf)
          if [ -n "$outdated_packages" ]; then
              _JobsPrint_Red "升级 fzf..."
              ask_run "升级 fzf？" && brew upgrade fzf
          else
              _JobsPrint_Green "fzf 已经是最新版本"
          fi
      fi
  }
  # 安装 Homebrew
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
  # 检查并安装 Homebrew
  check_homebrew() {
      if ! command -v brew &> /dev/null; then
          _JobsPrint_Red "brew 未安装，开始安装..."
          install_homebrew
          return 1
      else
          _JobsPrint_Red "Homebrew 已经安装，跳过安装步骤。"
          _JobsPrint_Red "检查更新 Homebrew..."
          brew update
          _JobsPrint_Red "升级 Homebrew 和由 Homebrew 管理的程序包..."
          brew upgrade
          _JobsPrint_Green "正在执行 Homebrew 清理工作..."

          if [ -d "/usr/local/Cellar/" ]; then
              sudo chown -R $(whoami) /usr/local/Cellar/
          fi
          if [ -d "$(brew --prefix)" ]; then
              sudo chown -R $(whoami) "$(brew --prefix)"/*
          fi
          brew cleanup
          _JobsPrint_Green "🍺🍺🍺完成更新和清理 Homebrew"
          brew doctor
          brew -v
          return 0
      fi
  }
  # 检查并安装 zsh
  check_and_install_zsh() {
      if command -v zsh >/dev/null 2>&1; then
          _JobsPrint_Red "zsh 已经安装，不需要执行任何操作。"
      else
          _JobsPrint_Red "zsh 未安装，正在通过 Homebrew 安装 zsh..."
          check_homebrew
          brew install zsh
      fi
  }
  # 定义提取文件名的方法
  extract_filename() {
      local filepath=$1
      local type=$2
      local filename=$(basename "$filepath")
    
      if [[ "$type" == "full" ]]; then
          echo "$filename"
      elif [[ "$type" == "no_ext" ]]; then
          echo "${filename%.*}"
      else
          echo "Invalid type. Use 'full' for full filename or 'no_ext' for filename without extension."
      fi
  }
  # 获取用户选择或确认项目名称
  get_project_names() {
      _JobsPrint_Red "查找 .xcodeproj 文件..."
      xcodeproj_files=($(find "$script_dir" -maxdepth 1 -name "*.xcodeproj"))

      if [[ ${#xcodeproj_files[@]} -eq 0 ]]; then
          _JobsPrint_Red "错误：当前目录下没有找到任何 .xcodeproj 文件"
          exit 1
      elif [[ ${#xcodeproj_files[@]} -eq 1 ]]; then
          default_old_project_name=$(extract_filename "$xcodeproj_files" "no_ext")
          _JobsPrint_Green "找到唯一的 .xcodeproj 文件：${default_old_project_name}.xcodeproj"
      else
          _JobsPrint_Green "找到多个 .xcodeproj 文件，请选择一个："
          selected_project=$(printf "%s\n" "${xcodeproj_files[@]}" | fzf --prompt "请选择旧项目名称：")
          default_old_project_name=$(basename "$selected_project" .xcodeproj)
      fi
  }
  # 删除 Pods 目录及其内容
  delete_pods() {
      _JobsPrint_Red "删除 Pods 目录及其内容..."
      if [[ -d "$script_dir/Pods" ]]; then
          rm -rf "$script_dir/Pods"
          _JobsPrint_Green "已删除 Pods 目录"
      else
          _JobsPrint_Red "Pods 目录不存在"
      fi
  }
  # 删除 Podfile.lock 文件
  delete_podfile_lock() {
      _JobsPrint_Red "删除 Podfile.lock 文件..."
      if [[ -f "$script_dir/Podfile.lock" ]]; then
          rm "$script_dir/Podfile.lock"
          _JobsPrint_Green "已删除 Podfile.lock 文件"
      else
          _JobsPrint_Red "Podfile.lock 文件不存在"
      fi
  }
  # 删除 .xcworkspace 文件
  delete_xcworkspace() {
      _JobsPrint_Red "删除 .xcworkspace 文件..."
      if [[ -d "$script_dir/${default_old_project_name}.xcworkspace" ]]; then
          rm -rf "$script_dir/${default_old_project_name}.xcworkspace"
          _JobsPrint_Green "已删除 ${default_old_project_name}.xcworkspace 文件"
      else
          _JobsPrint_Red "${default_old_project_name}.xcworkspace 文件不存在"
      fi
  }
  # 检查 当前目录下 *.xcworkspace 文件是否存在。如果存在则创建该文件的替身/快捷方式/别名 到桌面
  check_and_create_xcworkspace_shortcut(){
      WORKSPACE_FILE="$HOME/Desktop/${NEW_PROJECT_NAME}/${NEW_PROJECT_NAME}.xcworkspace"
      # 检查 .xcworkspace 文件是否存在
      if [[ -e "$WORKSPACE_FILE" ]]; then
          _JobsPrint_Red "*.xcworkspace 文件在："
          _JobsPrint_Green "$WORKSPACE_FILE"
          create_shortcut # 创建一份由 pod 创建的文件目录索引（*.xcworkspace）文件 替身/快捷方式/别名 到桌面
      else
          _JobsPrint_Red "错误：未找到 ${NEW_PROJECT_NAME}.xcworkspace 文件。"
      fi
  }
  # 创建一份由 pod 创建的文件目录索引（*.xcworkspace）文件 替身/快捷方式/别名 到桌面
  create_shortcut() {
  #    WORKSPACE_FILE="/Users/user/Desktop/JobsOCBaseConfigDemo/JobsOCBaseConfigDemo.xcworkspace"
      SHORTCUT_DESKTOP_PATH="$HOME/Desktop/${NEW_PROJECT_NAME}.xcworkspace"

      _JobsPrint_Red "尝试创建别名："
      _JobsPrint_Red "工作空间文件路径：$WORKSPACE_FILE"
      _JobsPrint_Red "桌面路径：$SHORTCUT_DESKTOP_PATH"

      # 创建桌面路径的目录（如果不存在）
      mkdir -p "$(dirname "$SHORTCUT_DESKTOP_PATH")"
      # 使用 ln 命令创建符号链接
      ln -s "$WORKSPACE_FILE" "$SHORTCUT_DESKTOP_PATH"

      if [ $? -eq 0 ]; then
          _JobsPrint_Green "已将 ${NEW_PROJECT_NAME}.xcworkspace 的快捷方式创建到桌面。"
      else
          _JobsPrint_Red "创建快捷方式失败。"
      fi
  }
  # 在指定路径下搜索并替换文件内容
  process_file() {
      local directory="$1"
      local filename_pattern="$2"
      local search_term="$3"
      local replace_term="$4"

      _JobsPrint_Green "directory = $directory"
      _JobsPrint_Green "filename_pattern = $filename_pattern"
      _JobsPrint_Green "search_term = $search_term"
      _JobsPrint_Green "replace_term = $replace_term"

      file_path=$(find "$directory" -type f -path "$directory/$filename_pattern")
      _JobsPrint_Green "file_path = $file_path" #
      if [[ -n "$file_path" ]]; then
          _JobsPrint_Green "正在处理文件：$file_path"
          search_and_replace "$file_path" "$search_term" "$replace_term"
      else
          _JobsPrint_Red "未找到符合条件的文件: $filename_pattern"
      fi
  }
  # 替换项目目录和文件名中的旧工程名
  replace_project_content() {
      _JobsPrint_Red "替换项目目录和文件名中的旧工程名..."
    
      _JobsPrint_Red "script_dir = $script_dir" # /Users/user/Desktop/Monkey
      _JobsPrint_Red "NEW_PROJECT_NAME = $NEW_PROJECT_NAME" # Monkey
      _JobsPrint_Red "default_old_project_name = $default_old_project_name" # JobsOCBaseConfig

      process_file "$script_dir" \
          "${NEW_PROJECT_NAME}Tests/${NEW_PROJECT_NAME}Tests.m" \
          "$default_old_project_name" \
          "$NEW_PROJECT_NAME"

      process_file "$script_dir" \
          "${NEW_PROJECT_NAME}UITests/${NEW_PROJECT_NAME}UITests.m" \
          "$default_old_project_name" \
          "$NEW_PROJECT_NAME"

      process_file "$script_dir" \
          "${NEW_PROJECT_NAME}UITests/${NEW_PROJECT_NAME}UITestsLaunchTests.m" \
          "$default_old_project_name" \
          "$NEW_PROJECT_NAME"

      _JobsPrint_Green "项目目录和文件名中的旧工程名替换完成"
  }
  # 替换 Podfile 文件中的旧工程名
  replace_podfile() {
      _JobsPrint_Red "替换 Podfile 文件中的旧工程名..."
      if [[ -f "$script_dir/Podfile" ]]; then
          search_and_replace "$script_dir/Podfile" "$default_old_project_name" "$NEW_PROJECT_NAME"
          search_and_replace "$script_dir/Podfile" "${default_old_project_name}Tests" "${NEW_PROJECT_NAME}Tests"
          search_and_replace "$script_dir/Podfile" "${default_old_project_name}UITests" "${NEW_PROJECT_NAME}UITests"
          _JobsPrint_Green "Podfile 文件中的旧工程名替换完成"
      else
          _JobsPrint_Red "Podfile 文件不存在"
      fi
  }
  # 重命名文件
  rename_file() {
      local old_path="$1"
      local new_path="$2"
      _JobsPrint_Green "尝试重命名文件：从 $old_path 到 $new_path"
      if [[ -f "$old_path" ]]; then
          echo "找到文件，准备重命名..."
          if mv "$old_path" "$new_path"; then
              _JobsPrint_Green "文件已成功重命名：$old_path -> $new_path"
          else
              _JobsPrint_Red "文件重命名失败：$old_path"
          fi
      else
          _JobsPrint_Red "文件未找到：$old_path"
      fi
  }
  # 其他的一些自定义的，需要手动配置的
  others() {
      ## 数据库
      mv "$DESKTOP_PATH/$NEW_PROJECT_NAME/其他/CoreData/${default_old_project_name}.xcdatamodeld" \
         "$DESKTOP_PATH/$NEW_PROJECT_NAME/其他/CoreData/${NEW_PROJECT_NAME}.xcdatamodeld"

      ## pch文件
      rename_file "$DESKTOP_PATH/$NEW_PROJECT_NAME/${default_old_project_name}PrefixHeader.pch" \
                  "$DESKTOP_PATH/$NEW_PROJECT_NAME/${NEW_PROJECT_NAME}PrefixHeader.pch"
  }
  # 重命名文件夹
  rename_folder() {
      local old_path="$1"
      local new_path="$2"
      _JobsPrint_Green "重命名前检查文件夹是否存在：$old_path"
      if [[ -d "$old_path" ]]; then
          if mv "$old_path" "$new_path"; then
              _JobsPrint_Green "文件夹已重命名：$old_path -> $new_path"
          else
              _JobsPrint_Red "文件夹重命名失败：$old_path"
          fi
      else
          _JobsPrint_Red "文件夹未找到：$old_path"
      fi
  }
  # 替换项目目录和文件名中的旧工程名
  replace_project_names() {
      _JobsPrint_Red "替换项目目录和文件名中的旧工程名..." #DESKTOP_PATH/
      rename_folder "$script_dir/${default_old_project_name}Tests" \
                    "$script_dir/${NEW_PROJECT_NAME}Tests"
      rename_file "$script_dir/${NEW_PROJECT_NAME}Tests/${default_old_project_name}Tests.m" \
                  "$script_dir/${NEW_PROJECT_NAME}Tests/${NEW_PROJECT_NAME}Tests.m"
      rename_folder "$script_dir/${default_old_project_name}UITests" \
                    "$script_dir/${NEW_PROJECT_NAME}UITests"
      rename_file "$script_dir/${NEW_PROJECT_NAME}UITests/${default_old_project_name}UITests.m" \
                  "$script_dir/${NEW_PROJECT_NAME}UITests/${NEW_PROJECT_NAME}UITests.m"
      rename_file "$script_dir/${NEW_PROJECT_NAME}UITests/${default_old_project_name}UITestsLaunchTests.m" \
                  "$script_dir/${NEW_PROJECT_NAME}UITests/${NEW_PROJECT_NAME}UITestsLaunchTests.m"
      rename_folder "$script_dir/${default_old_project_name}" \
                    "$script_dir/${NEW_PROJECT_NAME}"
      rename_file "$script_dir/${default_old_project_name}.xcodeproj" \
                  "$script_dir/${NEW_PROJECT_NAME}.xcodeproj"
      _JobsPrint_Green "项目目录和文件名中的旧工程名替换完成"
  }
  # 遍历某文件夹下的所有文件名 和 文件内容，对其进行字符串替换
  replace_in_files_and_filenames() {
      local dir_path="$1"
      local old_string="$2"
      local new_string="$3"

      # 遍历文件夹下所有文件，替换文件名中的 old_string 为 new_string
      find "$dir_path" -type f | while read -r file; do
          local base_name=$(basename "$file")
          local dir_name=$(dirname "$file")
          if [[ "$base_name" == *"$old_string"* ]]; then
              local new_base_name=${base_name//$old_string/$new_string}
              mv "$file" "$dir_name/$new_base_name"
          fi
      done

      # 遍历文件夹下所有文件，替换文件内容中的 old_string 为 new_string
      find "$dir_path" -type f | while read -r file; do
          sed -i.bak "s/$old_string/$new_string/g" "$file"
          rm "${file}.bak"
      done
  }
  # 处理 *.xcodeproj.project.pbxproj
  replace_pbxproj() {
      _JobsPrint_Red "替换 project.pbxproj 文件中的旧工程名..."
      local project_file_path="$script_dir/${default_old_project_name}.xcodeproj/project.pbxproj"
      search_and_replace "$project_file_path" "$default_old_project_name" "$NEW_PROJECT_NAME"
      _JobsPrint_Green "project.pbxproj 文件中的旧工程名替换完成"
  }
  # 替换 Info.plist 文件中的旧工程名
  replace_infoplist() {
      _JobsPrint_Red "替换 Info.plist 文件中的旧工程名..."
      find "$script_dir" -name "Info.plist" -exec sed -i '' "s/$default_old_project_name/$NEW_PROJECT_NAME/g" {} +
      _JobsPrint_Red "Info.plist 文件中的旧工程名替换完成"
  }
  # 替换 .xcscheme 文件中的旧工程名
  replace_xcscheme() {
      _JobsPrint_Red "替换 .xcscheme 文件中的旧工程名..."
      find "$script_dir" -name "*.xcscheme" -exec sed -i '' "s/$default_old_project_name/$NEW_PROJECT_NAME/g" {} +
      _JobsPrint_Green ".xcscheme 文件中的旧工程名替换完成"
  }
  # 处理符号链接（如果有）
  process_symlinks() {
      _JobsPrint_Red "处理符号链接（如果有）..."
      find "$script_dir" -type l -name "*$default_old_project_name*" | while read -r symlink; do
          target=$(readlink "$symlink")
          new_target=${target//$default_old_project_name/$NEW_PROJECT_NAME}
          ln -sf "$new_target" "$symlink"
      done
      _JobsPrint_Green "符号链接处理完成"
  }
  # 重命名 .xcodeproj 文件
  rename_xcodeproj() {
      _JobsPrint_Red "重命名 .xcodeproj 文件..."
      if [[ -d "$script_dir/${default_old_project_name}.xcodeproj" ]]; then
          mv "$script_dir/${default_old_project_name}.xcodeproj" "$script_dir/${NEW_PROJECT_NAME}.xcodeproj"
          _JobsPrint_Green "已重命名 .xcodeproj 文件"
      else
          _JobsPrint_Red ".xcodeproj 文件不存在"
      fi
  }
  # 重新安装 CocoaPods 依赖
  reinstall_pods() {
      _JobsPrint_Red "重新安装 CocoaPods 依赖..."
      (cd "$script_dir" && pod install)
      _JobsPrint_Green "显示依赖关系"
      cat Podfile.lock
      _JobsPrint_Green "CocoaPods 依赖安装完成"
  }
  # 主流程
  main() {
      jobs_logo # 打印 logo
      self_intro # 显示自述信息并等待用户回车
      prepare_environment # 检查并准备环境
      get_script_dir # 获取脚本所在目录

      copy_to_desk # 复制文件夹，排除.git目录，到桌面，并重命名为 $NEW_PROJECT_NAME

      get_project_names # 获取用户选择或确认项目名称
      delete_pods # 删除 Pods 目录及其内容
      delete_podfile_lock # 删除 Podfile.lock 文件
      delete_xcworkspace # 删除 .xcworkspace 文件
    
      replace_project_names # 处理文件夹名
      replace_project_content # 处理文件内容
    
      replace_podfile # 替换 Podfile 文件中的旧工程名
      replace_pbxproj # 处理 project.pbxproj 文件中的旧工程名
      rename_xcodeproj # 处理 .xcodeproj 文件

      replace_infoplist # 处理 Info.plist 文件中的旧工程名
      replace_xcscheme # 替换 .xcscheme 文件中的旧工程名
      process_symlinks # 处理符号链接（如果有）

      others # 其他的一些自定义的，需要手动配置的
      setup_git # 设置 Git 配置
      install_or_upgrade_jq # HomeBrew 安装或升级 jq
      check_and_set_mirror # 检查和设置镜像
      reinstall_pods # 重新安装 CocoaPods 依赖

      check_and_create_xcworkspace_shortcut # 检查 当前目录下 *.xcworkspace 文件是否存在。如果存在则创建该文件的替身/快捷方式/别名 到桌面
      _JobsPrint_Green "项目名称已成功从 $default_old_project_name 修改为 $NEW_PROJECT_NAME，并重新安装了 CocoaPods 依赖"
  }
  # 调用主函数
  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
