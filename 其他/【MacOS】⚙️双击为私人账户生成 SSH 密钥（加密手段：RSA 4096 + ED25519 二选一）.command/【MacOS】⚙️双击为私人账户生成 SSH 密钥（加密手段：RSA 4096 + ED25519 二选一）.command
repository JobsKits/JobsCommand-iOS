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
  # 全局变量声明
  typeset -g CURRENT_DIRECTORY=$(dirname "$(readlink -f "$0")") # 获取当前脚本文件的目录
  typeset -g default_personal_email="295060456@qq.com"
  typeset -g default_work_email="olive@vgtech.org"
  typeset -g personal_ssh_dir="$HOME/.ssh"
  typeset -g personal_ssh_key="$personal_ssh_dir/id_rsa_personal"
  typeset -g work_ssh_dir="$HOME/.ssh"
  typeset -g work_ssh_key="$work_ssh_dir/id_rsa_work"
  typeset -g default_key_type="ed25519" # 默认密钥类型
  echo -e "\033[1;31m$(basename "$(realpath "$0")")\033[0m" # 打印当前脚本的文件名
  # 通用打印方法
  _JobsPrint() {
      local COLOR="$1"
      local text="$2"
      local RESET="\033[0m"
      echo -e "${COLOR}${text}${RESET}"
  }
  # 定义红色加粗输出方法
  _JobsPrint_Red() {
      _JobsPrint "\033[1;31m" "$1"
  }
  # 定义绿色加粗输出方法
  _JobsPrint_Green() {
      _JobsPrint "\033[1;32m" "$1"
  }
  # 打印 "Jobs" logo
  jobs_logo() {
      local border="=="
      local width=49  # 根据logo的宽度调整
      local top_bottom_border=$(printf '%0.1s' "${border}"{1..$width})
      local logo="
  ||${top_bottom_border}||
  ||  JJJJJJJJ     oooooo    bb          SSSSSSSSSS  ||
  ||        JJ    oo    oo   bb          SS      SS  ||
  ||        JJ    oo    oo   bb          SS          ||
  ||        JJ    oo    oo   bbbbbbbbb   SSSSSSSSSS  ||
  ||  J     JJ    oo    oo   bb      bb          SS  ||
  ||  JJ    JJ    oo    oo   bb      bb  SS      SS  ||
  ||   JJJJJJ      oooooo     bbbbbbbb   SSSSSSSSSS  ||
  ||${top_bottom_border}||
  "
      _JobsPrint_Green "$logo"
  }
  # 自述信息
  self_intro() {
      _JobsPrint_Green "【MacOS】Setup_ssh_for_Github"

      _JobsPrint_Red "按回车键继续..."
      read
  }
  # 确认输入
  confirm_action() {
      local prompt="$1"
      local data="$2"
      local response
    
      echo "$prompt (直接回车同意，输入任意字符不同意): $2"
    
      read -r response
      if [[ -n "$response" ]]; then
          _JobsPrint_Red "操作已取消。"
          exit 1
      fi
  }
  # 选择密钥类型
  choose_key_type() {
      echo "请选择 SSH 密钥类型 (默认: ED25519):"
      echo "1) ED25519"
      echo "2) RSA 4096"
      read -p "请输入选择 (直接回车选择默认): " choice

      case "$choice" in
          1|"" )
              key_type="ed25519"
              ;;
          2 )
              key_type="rsa -b 4096"
              ;;
          * )
              _JobsPrint_Red "无效选择，使用默认的 ED25519。"
              key_type="ed25519"
              ;;
      esac
      _JobsPrint_Green "选择的密钥类型是: $key_type"
  }
  # 生成 SSH 密钥并添加到 ssh-agent
  generate_ssh_key() {
      local email="$1" # 这里接收邮箱
      local key_path="$2" # 这里接收 SSH 密钥路径
      _JobsPrint_Green "为 $email 生成 SSH 密钥"
      confirm_action "确认生成 SSH 密钥?" "(直接回车同意，输入任意字符不同意):"
      # 使用选择的密钥类型
      if [[ "$key_type" == "ed25519" ]]; then
          ssh-keygen -t ed25519 -C "$email" -f "$key_path" -N "" || {
              _JobsPrint_Red "密钥生成失败，请检查错误信息。"
              exit 1
          }
      else
          ssh-keygen -t rsa -b 4096 -C "$email" -f "$key_path" -N "" || {
              _JobsPrint_Red "密钥生成失败，请检查错误信息。"
              exit 1
          }
      fi
      # 输出公钥内容
      public_key=$(cat "$key_path.pub")
      echo "公钥是: $public_key"
    
      eval "$(ssh-agent -s)" || {
          _JobsPrint_Red "SSH agent 启动失败，请检查错误信息。"
          exit 1
      }

      ssh-add --apple-use-keychain "$key_path" || {
          _JobsPrint_Red "添加 SSH 密钥失败，请检查错误信息。"
          exit 1
      }
    
      _JobsPrint_Green "验证密钥是否加载..."
      ssh-add -l || {
          _JobsPrint_Red "加载 SSH 密钥失败。"
          exit 1
      }

      open https://github.com/settings/keys
      open https://github.com/settings/ssh/new
    
      _JobsPrint_Green "你的 $email 账户的公钥是："
      cat "$key_path.pub"
      _JobsPrint_Green "将公钥内容复制到剪切板..."
      cat "$key_path.pub" | pbcopy
      _JobsPrint_Green "公钥内容已复制到剪切板并打开 GitHub SSH 密钥设置页面，请手动粘贴添加。"
  }
  # 获取用户输入的 email
  get_email() {
      local prompt="$1"
      local default_email="$2"
      local email
      read -p "请输入 $prompt (默认: $default_email): " email
      if [[ -z "$email" ]]; then
          email="$default_email"
      fi
      echo "$email" # 返回用户输入的邮箱，不带格式
  }
  # 确保配置文件存在并添加配置
  setup_ssh_config() {
      local config_file="$personal_ssh_dir/config"
      if [[ ! -f "$config_file" ]]; then
          touch "$config_file"
          _JobsPrint_Green "创建 $config_file 文件"
      fi

      if ! grep -q "Host github.com" "$config_file"; then
          cat <<EOL >> "$config_file"
  Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    AddKeysToAgent yes
    UseKeychain yes
  EOL
          _JobsPrint_Green "已将 GitHub 配置添加到 $config_file"
      else
          _JobsPrint_Green "GitHub 配置已存在于 $config_file"
      fi
  }
  # 确保 SSH agent 每次启动时自动运行
  setup_ssh_agent() {
      local zshrc_file="$HOME/.zshrc"
      local bash_profile_file="$HOME/.bash_profile"
      local ssh_agent_cmd='eval "$(ssh-agent -s)"'

      for file in "$zshrc_file" "$bash_profile_file"; do
          if [[ -f "$file" ]] && ! grep -q "$ssh_agent_cmd" "$file"; then
              echo "$ssh_agent_cmd" >> "$file"
              _JobsPrint_Green "已将 SSH agent 启动命令添加到 $file"
          fi
      done
  }
  # 测试与 GitHub 和 GitLab 的 SSH 连接
  test_ssh_connection() {
      _JobsPrint_Green "只有在网页上粘贴了账户公钥，下面的测试连接 ssh -T git@github.com 才会正常..."
      read -p "按回车键继续，并测试与 GitHub 的 SSH 连接..."
      ssh -T git@github.com
      _JobsPrint_Green " SSH 设置完成！"
  }
  # 主函数
  main() {
      jobs_logo # 打印 "Jobs" logo
      self_intro # 自述信息
      open /Users/$(whoami)/.ssh
      choose_key_type # 选择密钥类型
      personal_email=$(get_email "个人邮箱" "$default_personal_email") # 获取无格式邮箱
      _JobsPrint_Green "个人邮箱是: $personal_email" # 打印无格式邮箱
      echo "SSH文件地址为: $personal_ssh_key"
      generate_ssh_key "$personal_email" "$personal_ssh_key" # 使用无格式邮箱
    
      setup_ssh_config # 设置 SSH 配置
      setup_ssh_agent # 设置 SSH agent 启动命令

      confirm_action "确认检查?" "(直接回车检查，输入任意字符不检查):"
      test_ssh_connection
    
      open https://github.com/settings/tokens
  }
  # 执行主函数
  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
run_main_flow() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
