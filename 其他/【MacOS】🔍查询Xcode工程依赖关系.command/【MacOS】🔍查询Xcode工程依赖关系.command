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
  set -u

  # ✅ 日志输出函数
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径

  log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
  color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
  info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
  success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
  warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
  warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
  note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
  error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
  err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
  debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
  highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
  gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
  bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
  underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

  # ✅ 自述信息：脚本启动后先展示用途、产物和注意事项。
  print_banner() {
    highlight_echo "═════════════════════════════════════════════════════════════════════"
    highlight_echo "🔍 Podspec 依赖分析器 - 查询 Xcode / CocoaPods 工程依赖关系"
    highlight_echo "═════════════════════════════════════════════════════════════════════"
  }

  # ✅ 打印脚本说明，并等待用户回车后继续。
  print_readme() {
    print_banner
    note_echo "功能说明："
    color_echo "1. 优先检测脚本所在目录和上一层目录；若包含 Podfile，则直接作为分析目录。"
    color_echo "2. 若自动检测不到，再让你拖入一个包含 Podfile 的目录。支持普通文件夹、Unix symlink、Finder 替身。"
    color_echo "3. 递归查找所有 *.podspec，并生成 Markdown 依赖报告，包含总览、0 依赖 Pod、明细和 Mermaid 图。"
    color_echo "4. 生成可搜索、可缩放、可拖拽的动态 HTML 依赖图。"
    color_echo "5. 会先自检 Homebrew；未安装时按芯片架构安装，再安装或升级 Graphviz 并尝试生成 PNG 图。"
    warm_echo ""
    warm_echo "输出目录会创建在你拖入的目标目录下：PodspecDependencyReport，新报告会覆盖旧数据。"
    info_echo "日志文件：$LOG_FILE"
    warm_echo ""
    bold_echo "准备好后按 Enter 继续..."
    IFS= read -r _
  }

  # ✅ 处理终端拖入路径：去掉引号、反斜杠转义，并展开成绝对路径。
  normalize_drag_path() {
    RAW_FOR_RUBY="$1" /usr/bin/ruby <<'RUBY'
  require 'shellwords'

  s = ENV.fetch('RAW_FOR_RUBY', '').strip

  begin
    parts = Shellwords.split(s)
    s = parts.join(' ') unless parts.empty?
  rescue ArgumentError
    s = s.gsub(/\\(.)/, '\\1')
    if (s.start_with?('"') && s.end_with?('"')) || (s.start_with?("'") && s.end_with?("'"))
      s = s[1...-1]
    end
  end

  puts File.expand_path(s)
  RUBY
  }

  # ✅ 解析真实路径：支持普通目录、普通 symlink、Finder「替身」。
  resolve_real_path() {
    local input_path="$1"
    local real_path=""
    local alias_resolved=""

    # 先处理普通目录、普通 symlink、Unix 路径规范化。
    real_path="$(REAL_PATH_FOR_RUBY="$input_path" /usr/bin/ruby <<'RUBY'
  path = ENV.fetch('REAL_PATH_FOR_RUBY', '').strip
  begin
    puts File.realpath(path)
  rescue
    puts File.expand_path(path)
  end
  RUBY
  )"

    if [[ -d "$real_path" ]]; then
      echo "$real_path"
      return 0
    fi

    # Finder「替身」不是普通 symlink，File.realpath 解析不了。
    # 注意：osascript 必须用 "-" 从 stdin 读取脚本，再把 input_path 当 argv 传进去。
    alias_resolved="$(/usr/bin/osascript - "$input_path" <<'APPLESCRIPT' 2>/dev/null || true
  on run argv
    set inputPath to item 1 of argv

    tell application "Finder"
      try
        set aliasFile to (POSIX file inputPath) as alias
        set originalItem to original item of aliasFile
        return POSIX path of (originalItem as alias)
      on error
        return ""
      end try
    end tell
  end run
  APPLESCRIPT
  )"

    alias_resolved="$(printf "%s" "$alias_resolved" | sed '/^[[:space:]]*$/d' | tail -n 1)"

    if [[ -n "${alias_resolved//[[:space:]]/}" ]]; then
      REAL_PATH_FOR_RUBY="$alias_resolved" /usr/bin/ruby <<'RUBY'
  path = ENV.fetch('REAL_PATH_FOR_RUBY', '').strip
  begin
    puts File.realpath(path)
  rescue
    puts File.expand_path(path)
  end
  RUBY
      return 0
    fi

    echo "$real_path"
  }

  # ✅ 判断目录是否可用：必须是目录，并且当前目录下直接包含 Podfile。
  is_valid_project_dir() {
    local dir="$1"

    [[ -d "$dir" && -f "$dir/Podfile" ]]
  }

  # ✅ 获取脚本所在目录。
  get_script_dir() {
    local script_path="${0:A}"
    dirname "$script_path"
  }

  # ✅ 最高优先级：自动检测脚本所在目录，以及脚本所在目录的上一层目录。
  # 如果其中任意目录直接包含 Podfile，就认为这是期望的工程目录。
  # 结果写入全局变量 SELECTED_TARGET_DIR。
  detect_target_dir_from_script_location() {
    local script_dir=""
    local parent_dir=""

    SELECTED_TARGET_DIR=""

    script_dir="$(get_script_dir)"
    parent_dir="$(dirname "$script_dir")"

    info_echo "优先检测脚本所在目录是否包含 Podfile：$script_dir"
    if is_valid_project_dir "$script_dir"; then
      SELECTED_TARGET_DIR="$script_dir"
      success_echo "已自动识别工程目录：$SELECTED_TARGET_DIR"
      return 0
    fi

    info_echo "继续检测脚本所在目录的上一层是否包含 Podfile：$parent_dir"
    if is_valid_project_dir "$parent_dir"; then
      SELECTED_TARGET_DIR="$parent_dir"
      success_echo "已自动识别工程目录：$SELECTED_TARGET_DIR"
      return 0
    fi

    warn_echo "脚本所在目录及上一层目录均未发现 Podfile，需要手动拖入包含 Podfile 的目录。"
    return 1
  }

  # ✅ 循环读取用户拖入的文件夹，直到得到有效目录。
  # 可用标准：必须是目录，并且该目录下直接包含 Podfile。
  # 结果写入全局变量 SELECTED_TARGET_DIR，避免日志输出被命令替换误捕获。
  prompt_target_dir() {
    local raw_path=""
    local input_path=""
    local target_dir=""

    SELECTED_TARGET_DIR=""

    while true; do
      warm_echo ""
      bold_echo "请把要分析的工程文件夹拖到这里，然后按 Enter（该目录下必须包含 Podfile）："
      IFS= read -r raw_path

      if [[ -z "${raw_path//[[:space:]]/}" ]]; then
        warn_echo "输入为空，请重新拖入文件夹。"
        continue
      fi

      input_path="$(normalize_drag_path "$raw_path")"
      target_dir="$(resolve_real_path "$input_path")"

      if is_valid_project_dir "$target_dir"; then
        SELECTED_TARGET_DIR="$target_dir"
        success_echo "已识别有效工程目录：$SELECTED_TARGET_DIR"
        return 0
      fi

      if [[ -d "$target_dir" ]]; then
        error_echo "目录存在，但当前目录下没有 Podfile：$target_dir"
      else
        error_echo "不是有效文件夹：$target_dir"
      fi
    done
  }

  # ✅ 获取当前 CPU 架构：arm64 或 x86_64。
  get_cpu_arch() {
    [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
  }

  # ✅ 根据架构推导 Homebrew 默认安装路径。
  get_brew_bin_by_arch() {
    local arch="$1"

    if [[ "$arch" == "arm64" ]]; then
      echo "/opt/homebrew/bin/brew"
    else
      echo "/usr/local/bin/brew"
    fi
  }

  # ✅ 根据当前 shell 推导 profile 文件。
  get_shell_profile_file() {
    local shell_path="${SHELL##*/}"

    case "$shell_path" in
      zsh)  echo "$HOME/.zprofile" ;;
      bash) echo "$HOME/.bash_profile" ;;
      *)    echo "$HOME/.profile" ;;
    esac
  }

  # ✅ 写入 Homebrew shellenv 到对应配置文件，并让当前终端立即生效。
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

  # ✅ Homebrew 自检：未安装时按芯片架构安装；已安装时询问是否更新、升级、清理和 doctor。
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

  # ✅ 检查 Graphviz：先做 Homebrew 自检，再执行 brew install / brew upgrade graphviz。
  ensure_graphviz() {
    warm_echo ""
    info_echo "检查 Graphviz..."

    install_homebrew || {
      warn_echo "Homebrew 自检或安装失败。动态 HTML 图仍会生成；PNG 图可能无法生成。"
      return 0
    }

    if command -v brew >/dev/null 2>&1; then
      if brew list --versions graphviz >/dev/null 2>&1; then
        info_echo "检测到 Graphviz 已通过 Homebrew 安装，开始升级..."
        brew upgrade graphviz 2>&1 | tee -a "$LOG_FILE" || true
      else
        info_echo "未检测到 Homebrew 版 Graphviz，开始安装..."
        brew install graphviz 2>&1 | tee -a "$LOG_FILE" || true
      fi
    fi

    if command -v dot >/dev/null 2>&1; then
      success_echo "Graphviz 可用：$(command -v dot)"
    else
      warn_echo "未检测到 dot 命令。动态 HTML 图仍会生成；PNG 图不会生成。"
    fi
  }

  # ✅ 创建报告输出目录：固定使用 PodspecDependencyReport，新的报告会删除并覆盖旧数据。
  prepare_report_dir() {
    local target_dir="$1"
    local report_dir="$target_dir/PodspecDependencyReport"

    if [[ -e "$report_dir" ]]; then
      # ⚠️ 注意：prepare_report_dir 会被 main 用命令替换接收返回值：
      # report_dir="$(prepare_report_dir "$target_dir")"
      # 所以这里的日志必须输出到 stderr，避免混进 report_dir 变量里。
      warn_echo "检测到旧报告目录，将删除并重新生成：$report_dir" >&2
      rm -rf "$report_dir"
    fi

    mkdir -p "$report_dir"
    echo "$report_dir"
  }

  # ✅ 写入 Ruby 解析器：复杂文本分析和报告生成交给 Ruby 处理。
  write_generator_script() {
    local generator="$1"

    cat > "$generator" <<'RUBY'
  require 'find'
  require 'set'
  require 'digest'
  require 'pathname'
  require 'json'

  root = File.expand_path(ARGV[0])
  out_dir = File.expand_path(ARGV[1])

  def strip_comment(line)
    result = +''
    quote = nil
    escaped = false

    line.each_char do |ch|
      if escaped
        result << ch
        escaped = false
        next
      end

      if quote
        if ch == '\\'
          result << ch
          escaped = true
        elsif ch == quote
          quote = nil
          result << ch
        else
          result << ch
        end
      else
        if ch == "'" || ch == '"'
          quote = ch
          result << ch
        elsif ch == '#'
          break
        else
          result << ch
        end
      end
    end

    result
  end

  def md_escape(value)
    value.to_s.gsub('\\', '\\\\').gsub('|', '\|').gsub("\n", ' ')
  end

  def mermaid_id(label)
    'N' + Digest::MD5.hexdigest(label.to_s)[0, 12]
  end

  def mermaid_label(label)
    label.to_s.gsub('"', "'")
  end

  def dot_escape(label)
    label.to_s.gsub('\\', '\\\\').gsub('"', '\"')
  end

  def rel_path(path, root)
    Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
  rescue
    path
  end

  def detail_anchor(pod_name)
    pod_name.to_s
  end

  def md_link_text_escape(value)
    md_escape(value).gsub('[', '\[').gsub(']', '\]')
  end

  def html_attr_escape(value)
    value.to_s.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
  end

  def local_pod_target(dep_name, pod_names)
    dep = dep_name.to_s
    return dep if pod_names.include?(dep)

    base = dep.split('/').first
    return base if pod_names.include?(base)

    nil
  end

  def pod_detail_link(label, pod_names, bold: false)
    target = local_pod_target(label, pod_names)
    escaped = md_link_text_escape(label)
    escaped = "**#{escaped}**" if bold

    return escaped unless target

    "[#{escaped}](##{detail_anchor(target)})"
  end

  def extract_first_source_url(line)
    github_match = line.match(%r{https?://github\.com/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)?})
    return github_match[0].sub(/\.git\z/, '') if github_match

    generic_match = line.match(%r{https?://[^\s'"<>)，,]+})
    return nil unless generic_match

    generic_match[0].sub(/[。；;，,、]+$/, '')
  end

  def collect_pod_source_urls(root)
    urls = {}
    podfile_paths = []

    Find.find(root) do |path|
      next unless File.file?(path)
      next if path.include?('/PodspecDependencyReport/')

      basename = File.basename(path)
      next unless basename == 'Podfile' ||
                  basename.start_with?('Podfile.') ||
                  basename.downcase.end_with?('.podfile')

      podfile_paths << path
    end

    podfile_paths.sort.each do |path|
      File.readlines(path, invalid: :replace, undef: :replace, replace: '').each do |line|
        # 支持正常 pod 行，也支持被注释掉的 pod 行：
        # pod 'GKNavigationBar' # https://github.com/QuintGao/GKNavigationBar
        # # pod 'BEMCheckBox'   # https://github.com/Boris-Em/BEMCheckBox
        pod_line = line.sub(/\A\s*#\s*/, '')
        next unless pod_line =~ /\bpod\s*\(?\s*['"]([^'"]+)['"]/

        pod_name = Regexp.last_match(1).strip
        source_url = extract_first_source_url(line)
        next if source_url.nil? || source_url.empty?

        urls[pod_name] ||= source_url

        base_name = pod_name.split('/').first
        urls[base_name] ||= source_url
      end
    rescue => e
      warn "读取 Podfile 来源注释失败：#{path} #{e.message}"
    end

    [urls, podfile_paths]
  end

  def dependency_link(dep_name, pod_names, source_urls)
    target = local_pod_target(dep_name, pod_names)
    return pod_detail_link(dep_name, pod_names) if target

    source_url = source_urls[dep_name.to_s] || source_urls[dep_name.to_s.split('/').first]
    return "[#{md_link_text_escape(dep_name)}](#{source_url})" if source_url && !source_url.empty?

    md_escape(dep_name)
  end


  def make_mermaid(edges, nodes = [])
    lines = ['flowchart LR']
    node_labels = nodes.to_set

    edges.each do |edge|
      node_labels << edge[:from]
      node_labels << edge[:to]
    end

    if edges.empty?
      if node_labels.empty?
        lines << '  EMPTY["未发现依赖关系"]'
      else
        node_labels.to_a.sort.each do |label|
          lines << %(  #{mermaid_id(label)}["#{mermaid_label(label)}"])
        end
      end
    else
      edges.map { |e| [e[:from], e[:to]] }.uniq.sort.each do |from, to|
        lines << %(  #{mermaid_id(from)}["#{mermaid_label(from)}"] --> #{mermaid_id(to)}["#{mermaid_label(to)}"])
      end
    end

    lines.join("\n")
  end

  def make_dot(edges, nodes = [])
    lines = []
    lines << 'digraph PodspecDependencies {'
    lines << '  rankdir=LR;'
    lines << '  graph [overlap=false, splines=true];'
    lines << '  node [shape=box, fontname="Helvetica"];'
    lines << '  edge [fontname="Helvetica"];'

    node_labels = nodes.to_set

    edges.each do |edge|
      node_labels << edge[:from]
      node_labels << edge[:to]
    end

    node_labels.to_a.sort.each do |label|
      lines << %(  "#{dot_escape(label)}";)
    end

    edges.map { |e| [e[:from], e[:to]] }.uniq.sort.each do |from, to|
      lines << %(  "#{dot_escape(from)}" -> "#{dot_escape(to)}";)
    end

    lines << '}'
    lines.join("\n")
  end

  def parse_podspec(path)
    text = File.read(path, invalid: :replace, undef: :replace, replace: '')
    lines = text.lines
    basename = File.basename(path, '.podspec')

    pod_name = nil

    lines.each do |line|
      cleaned = strip_comment(line)

      if pod_name.nil? && cleaned =~ /(?:^|[^\w])(?:\w+\.)?name\s*=\s*['"]([^'"]+)['"]/
        pod_name = Regexp.last_match(1).strip
      end
    end

    pod_name ||= basename

    deps = []
    depth = 0
    contexts = {}
    stack = []

    lines.each_with_index do |line, index|
      cleaned = strip_comment(line).strip
      next if cleaned.empty?

      if cleaned =~ /(?:^|[^\w])(\w+)\.subspec\s+['"]([^'"]+)['"]\s+do\s+\|(\w+)\|/
        parent_var = Regexp.last_match(1)
        sub_name = Regexp.last_match(2)
        sub_var = Regexp.last_match(3)

        parent_name = contexts[parent_var]&.first || pod_name
        full_name = "#{parent_name}/#{sub_name}"

        contexts[sub_var] = [full_name, depth + 1]
        stack << [sub_var, depth + 1]
      end

      cleaned.scan(/(?:(\w+(?:\.\w+)*)\.)?\bdependency\b\s*\(?\s*['"]([^'"]+)['"]([^#]*)/) do |receiver, dep_name, rest|
        receiver_var = receiver&.split('.')&.first

        declared_in = nil
        declared_in = contexts[receiver_var]&.first if receiver_var
        declared_in ||= contexts[stack.last&.first]&.first if receiver.nil? && stack.any?
        declared_in ||= pod_name

        requirement = rest.to_s.strip
        requirement = requirement.sub(/\A\s*,\s*/, '').strip
        requirement = requirement.sub(/\)\s*\z/, '').strip
        requirement = '' if requirement == ','

        deps << {
          dep: dep_name.strip,
          requirement: requirement,
          line: index + 1,
          declared_in: declared_in
        }
      end

      opens = cleaned.scan(/\bdo\b/).length + cleaned.count('{')
      closes = cleaned.scan(/\bend\b/).length + cleaned.count('}')
      depth += opens - closes

      while stack.any? && stack.last[1] > depth
        var, = stack.pop
        contexts.delete(var)
      end
    end

    deps.uniq! { |d| [d[:dep], d[:requirement], d[:declared_in], d[:line]] }

    {
      name: pod_name,
      path: path,
      deps: deps
    }
  end

  def make_interactive_html(data_json)
    <<~HTML
    <!doctype html>
    <html lang="zh-CN">
    <head>
      <meta charset="utf-8">
      <title>Podspec 依赖动态图</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root {
          color-scheme: light dark;
          --bg: #f6f7f9;
          --panel: #ffffff;
          --text: #1f2328;
          --muted: #667085;
          --border: #d0d7de;
          --node: #ffffff;
          --node-stroke: #667085;
          --node-internal: #e8f1ff;
          --node-external: #fff7e6;
          --edge: #8c959f;
          --highlight: #d1242f;
          --selected: #8250df;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --bg: #0d1117;
            --panel: #161b22;
            --text: #e6edf3;
            --muted: #8b949e;
            --border: #30363d;
            --node: #161b22;
            --node-stroke: #8b949e;
            --node-internal: #102a43;
            --node-external: #332600;
            --edge: #6e7681;
            --highlight: #ff7b72;
            --selected: #d2a8ff;
          }
        }

        * { box-sizing: border-box; }

        body {
          margin: 0;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, "PingFang SC", "Hiragino Sans GB", sans-serif;
          background: var(--bg);
          color: var(--text);
        }

        header {
          padding: 14px 18px;
          background: var(--panel);
          border-bottom: 1px solid var(--border);
          display: flex;
          gap: 12px;
          align-items: center;
          flex-wrap: wrap;
        }

        header h1 {
          font-size: 18px;
          margin: 0 12px 0 0;
        }

        .control {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 13px;
          color: var(--muted);
        }

        input, select, button {
          font: inherit;
          border: 1px solid var(--border);
          border-radius: 8px;
          padding: 7px 9px;
          background: var(--panel);
          color: var(--text);
        }

        button {
          cursor: pointer;
        }

        button:hover {
          border-color: var(--selected);
        }

        #layout {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 360px;
          height: calc(100vh - 64px);
        }

        #graphWrap {
          position: relative;
          overflow: hidden;
        }

        #graph {
          width: 100%;
          height: 100%;
          display: block;
          cursor: grab;
        }

        #graph:active {
          cursor: grabbing;
        }

        aside {
          border-left: 1px solid var(--border);
          background: var(--panel);
          padding: 14px;
          overflow: auto;
        }

        .hint, .meta {
          color: var(--muted);
          font-size: 13px;
          line-height: 1.55;
        }

        .badge {
          display: inline-block;
          border: 1px solid var(--border);
          border-radius: 999px;
          padding: 2px 8px;
          margin: 2px;
          font-size: 12px;
          color: var(--muted);
        }

        .node rect {
          fill: var(--node);
          stroke: var(--node-stroke);
          stroke-width: 1.4;
          rx: 10;
          ry: 10;
          filter: drop-shadow(0 2px 4px rgba(0,0,0,0.12));
        }

        .node.internal rect { fill: var(--node-internal); }
        .node.external rect { fill: var(--node-external); }
        .node.highlight rect { stroke: var(--highlight); stroke-width: 3; }
        .node.selected rect { stroke: var(--selected); stroke-width: 3; }

        .node text {
          fill: var(--text);
          font-size: 12px;
          pointer-events: none;
        }

        .node .subtext {
          fill: var(--muted);
          font-size: 10px;
        }

        .edge {
          fill: none;
          stroke: var(--edge);
          stroke-width: 1.4;
          marker-end: url(#arrow);
        }

        .edge.highlight {
          stroke: var(--highlight);
          stroke-width: 2.6;
        }

        .edge.selected {
          stroke: var(--selected);
          stroke-width: 2.8;
        }

        .empty {
          padding: 20px;
          color: var(--muted);
        }

        .section {
          margin-top: 16px;
        }

        .section h3 {
          font-size: 14px;
          margin: 0 0 8px 0;
        }

        .list {
          padding-left: 18px;
          margin: 6px 0;
          font-size: 13px;
          line-height: 1.55;
        }

        code {
          background: color-mix(in srgb, var(--border) 35%, transparent);
          border-radius: 4px;
          padding: 1px 4px;
        }

        @media (max-width: 900px) {
          #layout {
            grid-template-columns: 1fr;
            grid-template-rows: minmax(420px, 65vh) auto;
          }

          aside {
            border-left: none;
            border-top: 1px solid var(--border);
          }
        }
      </style>
    </head>
    <body>
      <header>
        <h1>Podspec 依赖动态图</h1>

        <label class="control">
          图类型
          <select id="mode">
            <option value="internal">只看仓库内 Pod 关联</option>
            <option value="all">全部依赖</option>
          </select>
        </label>

        <label class="control">
          搜索
          <input id="search" placeholder="输入 Pod 名称过滤" />
        </label>

        <label class="control">
          邻居层级
          <select id="depth">
            <option value="1">1 层</option>
            <option value="2">2 层</option>
            <option value="3">3 层</option>
            <option value="99">全部关联</option>
          </select>
        </label>

        <button id="fit">适配视图</button>
        <button id="reset">重置</button>
      </header>

      <div id="layout">
        <main id="graphWrap">
          <svg id="graph">
            <defs>
              <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--edge)"></path>
              </marker>
            </defs>
            <g id="viewport">
              <g id="edges"></g>
              <g id="nodes"></g>
            </g>
          </svg>
        </main>

        <aside id="side">
          <div class="hint">
            用法：滚轮缩放，拖动画布平移，拖动节点调整位置。点击节点可以只看它附近的依赖关系；搜索框会保留命中的节点及其上下游。
          </div>
        </aside>
      </div>

      <script>
        const DATA = #{data_json};

        const svg = document.getElementById('graph');
        const viewport = document.getElementById('viewport');
        const edgeLayer = document.getElementById('edges');
        const nodeLayer = document.getElementById('nodes');
        const side = document.getElementById('side');

        const state = {
          mode: 'internal',
          search: '',
          focus: null,
          depth: 1,
          scale: 1,
          tx: 60,
          ty: 60,
          nodes: [],
          edges: [],
          visibleNodes: [],
          visibleEdges: []
        };

        const internalPods = new Set(DATA.pods.map(p => p.name));

        function shortType(name) {
          const base = name.split('/')[0];
          return internalPods.has(base) ? 'internal' : 'external';
        }

        function collectGraph() {
          const sourceEdges = state.mode === 'internal' ? DATA.internalEdges : DATA.allEdges;
          const nodeMap = new Map();

          DATA.pods.forEach(p => {
            nodeMap.set(p.name, {
              id: p.name,
              label: p.name,
              type: 'internal',
              file: p.file,
              depCount: p.deps.length
            });
          });

          sourceEdges.forEach(e => {
            if (!nodeMap.has(e.from)) {
              nodeMap.set(e.from, { id: e.from, label: e.from, type: shortType(e.from), depCount: 0 });
            }
            if (!nodeMap.has(e.to)) {
              nodeMap.set(e.to, { id: e.to, label: e.to, type: shortType(e.to), depCount: 0 });
            }
          });

          const edgeMap = new Map();
          sourceEdges.forEach(e => {
            const key = `${e.from}|||${e.to}`;
            if (!edgeMap.has(key)) {
              edgeMap.set(key, {
                from: e.from,
                to: e.to,
                details: []
              });
            }
            edgeMap.get(key).details.push(e);
          });

          state.nodes = Array.from(nodeMap.values());
          state.edges = Array.from(edgeMap.values());
          layoutNodes();
        }

        function layoutNodes() {
          const indegree = new Map(state.nodes.map(n => [n.id, 0]));
          const outgoing = new Map(state.nodes.map(n => [n.id, []]));

          state.edges.forEach(e => {
            indegree.set(e.to, (indegree.get(e.to) || 0) + 1);
            outgoing.get(e.from)?.push(e.to);
          });

          const level = new Map(state.nodes.map(n => [n.id, 0]));
          const queue = [];

          indegree.forEach((count, id) => {
            if (count === 0) queue.push(id);
          });

          if (queue.length === 0) {
            state.nodes.forEach(n => {
              if (n.type === 'internal') queue.push(n.id);
            });
          }

          const seen = new Set(queue);

          while (queue.length) {
            const id = queue.shift();
            const nextLevel = (level.get(id) || 0) + 1;

            (outgoing.get(id) || []).forEach(to => {
              level.set(to, Math.max(level.get(to) || 0, nextLevel));
              indegree.set(to, Math.max(0, (indegree.get(to) || 0) - 1));

              if (indegree.get(to) === 0 && !seen.has(to)) {
                seen.add(to);
                queue.push(to);
              }
            });
          }

          const groups = new Map();

          state.nodes.forEach(n => {
            const l = Math.min(level.get(n.id) || 0, 10);
            if (!groups.has(l)) groups.set(l, []);
            groups.get(l).push(n);
          });

          groups.forEach(list => {
            list.sort((a, b) => {
              if (a.type !== b.type) return a.type === 'internal' ? -1 : 1;
              return a.label.localeCompare(b.label);
            });
          });

          const xGap = 250;
          const yGap = 86;

          groups.forEach((list, l) => {
            const totalHeight = Math.max(0, (list.length - 1) * yGap);
            list.forEach((n, index) => {
              n.x = l * xGap;
              n.y = index * yGap - totalHeight / 2;
              n.w = Math.max(130, Math.min(240, n.label.length * 8 + 34));
              n.h = 46;
            });
          });
        }

        function neighborsOf(ids, depth) {
          const result = new Set(ids);
          let frontier = new Set(ids);

          for (let i = 0; i < depth; i++) {
            const next = new Set();

            state.edges.forEach(e => {
              if (frontier.has(e.from)) next.add(e.to);
              if (frontier.has(e.to)) next.add(e.from);
            });

            next.forEach(id => {
              if (!result.has(id)) {
                result.add(id);
              }
            });

            frontier = next;
          }

          return result;
        }

        function computeVisible() {
          let ids = new Set(state.nodes.map(n => n.id));
          const search = state.search.trim().toLowerCase();

          if (search) {
            const matched = state.nodes
              .filter(n => n.label.toLowerCase().includes(search))
              .map(n => n.id);

            ids = neighborsOf(matched, Number(state.depth));
          }

          if (state.focus) {
            ids = neighborsOf([state.focus], Number(state.depth));
          }

          state.visibleNodes = state.nodes.filter(n => ids.has(n.id));
          const visibleIdSet = new Set(state.visibleNodes.map(n => n.id));
          state.visibleEdges = state.edges.filter(e => visibleIdSet.has(e.from) && visibleIdSet.has(e.to));
        }

        function applyTransform() {
          viewport.setAttribute('transform', `translate(${state.tx}, ${state.ty}) scale(${state.scale})`);
        }

        function edgePath(e) {
          const from = state.nodes.find(n => n.id === e.from);
          const to = state.nodes.find(n => n.id === e.to);

          if (!from || !to) return '';

          const x1 = from.x + from.w / 2;
          const y1 = from.y;
          const x2 = to.x - to.w / 2;
          const y2 = to.y;

          const dx = Math.max(60, Math.abs(x2 - x1) * 0.45);
          return `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
        }

        function render() {
          computeVisible();

          edgeLayer.innerHTML = '';
          nodeLayer.innerHTML = '';

          const visibleEdgeKeys = new Set();

          state.visibleEdges.forEach(e => {
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('class', 'edge');
            path.setAttribute('d', edgePath(e));
            path.dataset.from = e.from;
            path.dataset.to = e.to;

            if (state.focus && (e.from === state.focus || e.to === state.focus)) {
              path.classList.add('selected');
            }

            edgeLayer.appendChild(path);
            visibleEdgeKeys.add(`${e.from}|||${e.to}`);
          });

          const search = state.search.trim().toLowerCase();

          state.visibleNodes.forEach(n => {
            const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            g.setAttribute('class', `node ${n.type}`);
            g.setAttribute('transform', `translate(${n.x - n.w / 2}, ${n.y - n.h / 2})`);
            g.dataset.id = n.id;

            if (search && n.label.toLowerCase().includes(search)) {
              g.classList.add('highlight');
            }

            if (state.focus === n.id) {
              g.classList.add('selected');
            }

            const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
            rect.setAttribute('width', n.w);
            rect.setAttribute('height', n.h);

            const title = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            title.setAttribute('x', 12);
            title.setAttribute('y', 19);
            title.textContent = n.label.length > 26 ? n.label.slice(0, 25) + '…' : n.label;

            const sub = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            sub.setAttribute('class', 'subtext');
            sub.setAttribute('x', 12);
            sub.setAttribute('y', 35);
            sub.textContent = n.type === 'internal' ? `仓库内 Pod · ${n.depCount || 0} 个依赖` : '外部依赖';

            g.appendChild(rect);
            g.appendChild(title);
            g.appendChild(sub);

            g.addEventListener('click', event => {
              event.stopPropagation();
              state.focus = state.focus === n.id ? null : n.id;
              render();
              updateSide(n.id);
            });

            makeNodeDraggable(g, n);
            nodeLayer.appendChild(g);
          });

          updateSide(state.focus);
        }

        function makeNodeDraggable(el, node) {
          let dragging = false;
          let start = null;

          el.addEventListener('mousedown', event => {
            dragging = true;
            start = {
              x: event.clientX,
              y: event.clientY,
              nodeX: node.x,
              nodeY: node.y
            };
            event.stopPropagation();
          });

          window.addEventListener('mousemove', event => {
            if (!dragging) return;

            node.x = start.nodeX + (event.clientX - start.x) / state.scale;
            node.y = start.nodeY + (event.clientY - start.y) / state.scale;

            render();
          });

          window.addEventListener('mouseup', () => {
            dragging = false;
          });
        }

        function renderZeroDependencyPods() {
          const zeroPods = DATA.pods
            .filter(p => !p.deps || p.deps.length === 0)
            .map(p => p.name)
            .sort((a, b) => a.localeCompare(b));

          if (!zeroPods.length) {
            return '<div class="meta">没有 0 依赖 Pod。</div>';
          }

          return `<ul class="list">${zeroPods.map(name => `<li><b>${escapeHtml(name)}</b></li>`).join('')}</ul>`;
        }

        function updateSide(id) {
          const modeName = state.mode === 'internal' ? '仓库内关联' : '全部依赖';
          const visibleInfo = `<div class="meta">
            <span class="badge">${modeName}</span>
            <span class="badge">节点 ${state.visibleNodes.length} / ${state.nodes.length}</span>
            <span class="badge">关系 ${state.visibleEdges.length} / ${state.edges.length}</span>
          </div>`;

          if (!id) {
            side.innerHTML = `
              <div class="hint">
                用法：滚轮缩放，拖动画布平移，拖动节点调整位置。点击节点可以只看它附近的依赖关系；搜索框会保留命中的节点及其上下游。
              </div>
              <div class="section">${visibleInfo}</div>
              <div class="section">
                <h3>报告信息</h3>
                <div class="meta">
                  <div>目录：<code>${escapeHtml(DATA.root)}</code></div>
                  <div>生成时间：<code>${escapeHtml(DATA.generatedAt)}</code></div>
                </div>
              </div>
              <div class="section">
                <h3>0 依赖 Pod</h3>
                ${renderZeroDependencyPods()}
              </div>
            `;
            return;
          }

          const node = state.nodes.find(n => n.id === id);
          const outgoing = state.edges.filter(e => e.from === id);
          const incoming = state.edges.filter(e => e.to === id);

          const depList = outgoing.length
            ? `<ul class="list">${outgoing.map(e => `<li><b>${escapeHtml(e.to)}</b>${renderDetails(e.details)}</li>`).join('')}</ul>`
            : '<div class="meta">没有发现它依赖其他 Pod。</div>';

          const usedByList = incoming.length
            ? `<ul class="list">${incoming.map(e => `<li><b>${escapeHtml(e.from)}</b>${renderDetails(e.details)}</li>`).join('')}</ul>`
            : '<div class="meta">没有发现其他 Pod 依赖它。</div>';

          side.innerHTML = `
            ${visibleInfo}
            <div class="section">
              <h3>${escapeHtml(id)}</h3>
              <div class="meta">
                <span class="badge">${node?.type === 'internal' ? '仓库内 Pod' : '外部依赖'}</span>
                ${node?.file ? `<div>Podspec：<code>${escapeHtml(node.file)}</code></div>` : ''}
              </div>
            </div>
            <div class="section">
              <h3>它依赖了</h3>
              ${depList}
            </div>
            <div class="section">
              <h3>谁依赖它</h3>
              ${usedByList}
            </div>
          `;
        }

        function renderDetails(details) {
          if (!details || !details.length) return '';

          const lines = details.slice(0, 5).map(d => {
            const req = d.requirement ? `，版本/参数：<code>${escapeHtml(d.requirement)}</code>` : '';
            const declared = d.declaredIn ? `，声明位置：<code>${escapeHtml(d.declaredIn)}</code>` : '';
            return `<div class="meta">行 ${d.line || '-'}${req}${declared}</div>`;
          });

          if (details.length > 5) {
            lines.push(`<div class="meta">还有 ${details.length - 5} 条声明...</div>`);
          }

          return lines.join('');
        }

        function escapeHtml(value) {
          return String(value ?? '')
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
        }

        function fitView() {
          computeVisible();

          if (!state.visibleNodes.length) return;

          const wrap = document.getElementById('graphWrap');
          const minX = Math.min(...state.visibleNodes.map(n => n.x - n.w / 2));
          const maxX = Math.max(...state.visibleNodes.map(n => n.x + n.w / 2));
          const minY = Math.min(...state.visibleNodes.map(n => n.y - n.h / 2));
          const maxY = Math.max(...state.visibleNodes.map(n => n.y + n.h / 2));

          const width = Math.max(1, maxX - minX);
          const height = Math.max(1, maxY - minY);
          const scaleX = (wrap.clientWidth - 80) / width;
          const scaleY = (wrap.clientHeight - 80) / height;

          state.scale = Math.max(0.15, Math.min(1.6, Math.min(scaleX, scaleY)));
          state.tx = 40 - minX * state.scale;
          state.ty = 40 - minY * state.scale;

          applyTransform();
        }

        let panning = false;
        let panStart = null;

        svg.addEventListener('mousedown', event => {
          panning = true;
          panStart = {
            x: event.clientX,
            y: event.clientY,
            tx: state.tx,
            ty: state.ty
          };
        });

        window.addEventListener('mousemove', event => {
          if (!panning) return;

          state.tx = panStart.tx + event.clientX - panStart.x;
          state.ty = panStart.ty + event.clientY - panStart.y;
          applyTransform();
        });

        window.addEventListener('mouseup', () => {
          panning = false;
        });

        svg.addEventListener('click', () => {
          state.focus = null;
          render();
        });

        svg.addEventListener('wheel', event => {
          event.preventDefault();

          const rect = svg.getBoundingClientRect();
          const mx = event.clientX - rect.left;
          const my = event.clientY - rect.top;
          const beforeX = (mx - state.tx) / state.scale;
          const beforeY = (my - state.ty) / state.scale;

          const factor = event.deltaY < 0 ? 1.1 : 0.9;
          state.scale = Math.max(0.08, Math.min(4, state.scale * factor));

          state.tx = mx - beforeX * state.scale;
          state.ty = my - beforeY * state.scale;

          applyTransform();
        }, { passive: false });

        document.getElementById('mode').addEventListener('change', event => {
          state.mode = event.target.value;
          state.focus = null;
          collectGraph();
          render();
          fitView();
        });

        document.getElementById('search').addEventListener('input', event => {
          state.search = event.target.value;
          state.focus = null;
          render();
          fitView();
        });

        document.getElementById('depth').addEventListener('change', event => {
          state.depth = Number(event.target.value);
          render();
          fitView();
        });

        document.getElementById('fit').addEventListener('click', () => {
          fitView();
        });

        document.getElementById('reset').addEventListener('click', () => {
          state.search = '';
          state.focus = null;
          state.depth = 1;
          document.getElementById('search').value = '';
          document.getElementById('depth').value = '1';
          collectGraph();
          render();
          fitView();
        });

        collectGraph();
        render();
        fitView();
        applyTransform();
      </script>
    </body>
    </html>
    HTML
  end

  podspec_paths = []

  Find.find(root) do |path|
    next unless File.file?(path)
    podspec_paths << path if path.end_with?('.podspec')
  end

  podspec_paths.sort!

  reports = []
  errors = []

  podspec_paths.each do |path|
    begin
      reports << parse_podspec(path)
    rescue => e
      errors << [path, e.message]
    end
  end

  pod_names = reports.map { |r| r[:name] }.to_set
  all_edges = []
  internal_edges = []

  reports.each do |report|
    report[:deps].each do |dep|
      edge = {
        from: report[:name],
        to: dep[:dep],
        requirement: dep[:requirement],
        declared_in: dep[:declared_in],
        line: dep[:line],
        file: rel_path(report[:path], root)
      }

      all_edges << edge

      dep_base_name = dep[:dep].split('/').first
      internal_edges << edge if pod_names.include?(dep_base_name)
    end
  end

  all_nodes = reports.map { |r| r[:name] }
  zero_dependency_reports = reports.select { |r| r[:deps].empty? }.sort_by { |r| r[:name] }
  source_urls, source_podfile_paths = collect_pod_source_urls(root)

  md_path = File.join(out_dir, 'PodspecDependencies.md')
  html_path = File.join(out_dir, 'PodspecDependencies_interactive.html')
  all_mmd_path = File.join(out_dir, 'PodspecDependencies_all.mmd')
  internal_mmd_path = File.join(out_dir, 'PodspecDependencies_internal.mmd')
  all_dot_path = File.join(out_dir, 'PodspecDependencies_all.dot')
  internal_dot_path = File.join(out_dir, 'PodspecDependencies_internal.dot')

  all_mermaid = make_mermaid(all_edges, all_nodes)
  internal_mermaid = make_mermaid(internal_edges, all_nodes)

  File.write(all_mmd_path, all_mermaid)
  File.write(internal_mmd_path, internal_mermaid)
  File.write(all_dot_path, make_dot(all_edges, all_nodes))
  File.write(internal_dot_path, make_dot(internal_edges, all_nodes))

  html_data = {
    root: root,
    generatedAt: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    pods: reports.sort_by { |r| r[:name] }.map do |r|
      {
        name: r[:name],
        file: rel_path(r[:path], root),
        deps: r[:deps]
      }
    end,
    allEdges: all_edges,
    internalEdges: internal_edges
  }

  File.write(html_path, make_interactive_html(JSON.generate(html_data)))

  File.open(md_path, 'w') do |md|
    top_link = '<a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>'

    md.puts '# Podspec 依赖分析报告'
    md.puts '![Jobs倾情奉献](https://picsum.photos/1500/400 "Jobs出品，必属精品")'
    md.puts '[toc]'
    md.puts
    md.puts "## 🔥 <font id=前言>前言</font> #{top_link}"
    md.puts
    md.puts "- 分析目录：`#{root}`"
    md.puts "- 生成时间：`#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}`"
    md.puts "- Podspec 数量：`#{reports.length}`"
    md.puts "- 0 依赖 Pod 数量：`#{zero_dependency_reports.length}`"
    md.puts "- 全部依赖边数量：`#{all_edges.map { |e| [e[:from], e[:to]] }.uniq.length}`"
    md.puts "- 仓库内 Pod 依赖边数量：`#{internal_edges.map { |e| [e[:from], e[:to]] }.uniq.length}`"
    md.puts "- 外部依赖来源注释文件数量：`#{source_podfile_paths.length}`"
    md.puts "- 已识别外部依赖来源链接数量：`#{source_urls.length}`"
    md.puts
    md.puts "> 更易读的动态关系图见：`PodspecDependencies_interactive.html`。"
    md.puts

    if podspec_paths.empty?
      md.puts '> 没有找到任何 `.podspec` 文件。'
      md.puts
      md.puts '<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>'
      next
    end

    unless errors.empty?
      md.puts '#### 解析失败的文件'
      md.puts
      md.puts '| Podspec | 错误 |'
      md.puts '|---|---|'
      errors.each do |path, message|
        rel = rel_path(path, root)
        md.puts "| **`#{md_escape(rel)}`** | #{md_escape(message)} |"
      end
      md.puts
    end

    md.puts "## 一、总览 #{top_link}"
    md.puts
    md.puts '| Pod | Podspec | 依赖数量 | 依赖 |'
    md.puts '|---|---|---:|---|'

    reports.sort_by { |r| r[:name] }.each do |report|
      rel = rel_path(report[:path], root)
      deps = report[:deps].map { |d| d[:dep] }.uniq.sort
      dep_links = deps.map { |dep_name| dependency_link(dep_name, pod_names, source_urls) }.join(', ')
      md.puts "| #{pod_detail_link(report[:name], pod_names, bold: true)} | `#{md_escape(rel)}` | #{deps.length} | #{dep_links} |"
    end

    md.puts
    md.puts "## 二、0 依赖 Pod #{top_link}"
    md.puts

    if zero_dependency_reports.empty?
      md.puts '没有 0 依赖 Pod。'
    else
      md.puts '| Pod | Podspec |'
      md.puts '|---|---|'
      zero_dependency_reports.each do |report|
        rel = rel_path(report[:path], root)
        md.puts "| #{pod_detail_link(report[:name], pod_names, bold: true)} | `#{md_escape(rel)}` |"
      end
    end

    md.puts
    md.puts "## 三、仓库内 Pod 相互依赖图 Mermaid #{top_link}"
    md.puts
    md.puts '只展示依赖目标也在本次扫描到的 `.podspec` 里存在的关系。'
    md.puts
    md.puts '```mermaid'
    md.puts internal_mermaid
    md.puts '```'
    md.puts

    md.puts "## 四、全部依赖图 Mermaid #{top_link}"
    md.puts
    md.puts '```mermaid'
    md.puts all_mermaid
    md.puts '```'
    md.puts

    md.puts "## 五、明细 #{top_link}"

    reports.sort_by { |r| r[:name] }.each_with_index do |report, index|
      rel = rel_path(report[:path], root)

      md.puts
      md.puts %(### #{index + 1}、<font id="#{html_attr_escape(detail_anchor(report[:name]))}">#{md_escape(report[:name])}</font> #{top_link})
      md.puts
      md.puts "Podspec：`#{rel}`"
      md.puts

      if report[:deps].empty?
        md.puts '未发现依赖。'
        next
      end

      md.puts '| 声明位置 | 依赖 | 版本/参数 |'
      md.puts '|---|---|---|'

      report[:deps].sort_by { |d| [d[:declared_in], d[:dep], d[:line]] }.each do |dep|
        declared_link = pod_detail_link(dep[:declared_in], pod_names, bold: true)
        dep_link = dependency_link(dep[:dep], pod_names, source_urls)
        md.puts "| #{declared_link} | #{dep_link} | `#{md_escape(dep[:requirement])}` |"
      end
    end

    md.puts
    md.puts "## 六、生成的文件 #{top_link}"
    md.puts
    md.puts '- `PodspecDependencies_interactive.html`：可搜索、可拖拽、可缩放动态图'
    md.puts '- `PodspecDependencies.md`：本报告'
    md.puts '- `PodspecDependencies_all.mmd`：全部依赖 Mermaid 图源码'
    md.puts '- `PodspecDependencies_internal.mmd`：仓库内 Pod 相互依赖 Mermaid 图源码'
    md.puts '- `PodspecDependencies_all.dot`：全部依赖 Graphviz DOT 源码'
    md.puts '- `PodspecDependencies_internal.dot`：仓库内 Pod 相互依赖 Graphviz DOT 源码'
    md.puts
    md.puts '<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>'
  end

  puts md_path
  puts html_path
  RUBY
  }

  # ✅ 执行 Ruby 解析器并生成 Markdown、HTML、Mermaid、DOT 文件。
  run_generator() {
    local generator="$1"
    local target_dir="$2"
    local report_dir="$3"
    local generator_exit_code=0

    info_echo "开始扫描并生成依赖报告..."

    /usr/bin/ruby "$generator" "$target_dir" "$report_dir" 2>&1 | tee -a "$LOG_FILE"
    generator_exit_code=${pipestatus[1]}

    rm -f "$generator"

    if [[ $generator_exit_code -ne 0 ]]; then
      error_echo "生成失败，状态码：$generator_exit_code"
      exit $generator_exit_code
    fi

    success_echo "依赖报告生成完成。"
  }

  # ✅ 如果系统可用 dot，则额外生成 Graphviz PNG 图片。
  generate_graphviz_png() {
    local report_dir="$1"
    local dot_all="$report_dir/PodspecDependencies_all.dot"
    local dot_internal="$report_dir/PodspecDependencies_internal.dot"
    local png_all="$report_dir/PodspecDependencies_all.png"
    local png_internal="$report_dir/PodspecDependencies_internal.png"

    if command -v dot >/dev/null 2>&1; then
      info_echo "开始生成 Graphviz PNG 图片..."
      dot -Tpng "$dot_all" -o "$png_all" 2>&1 | tee -a "$LOG_FILE" || true
      dot -Tpng "$dot_internal" -o "$png_internal" 2>&1 | tee -a "$LOG_FILE" || true

      warm_echo ""
      success_echo "已生成 Graphviz PNG："
      [[ -f "$png_all" ]] && color_echo "$png_all"
      [[ -f "$png_internal" ]] && color_echo "$png_internal"
    else
      warn_echo "未检测到 dot 命令，跳过 PNG 生成。"
    fi
  }

  # ✅ 打开主要产物：动态 HTML、Markdown 报告和仓库内 PNG 图。
  open_outputs() {
    local report_dir="$1"
    local md_file="$report_dir/PodspecDependencies.md"
    local html_file="$report_dir/PodspecDependencies_interactive.html"
    local png_internal="$report_dir/PodspecDependencies_internal.png"

    [[ -f "$html_file" ]] && open "$html_file"
    [[ -f "$md_file" ]] && open "$md_file"
    [[ -f "$png_internal" ]] && open "$png_internal"

    warm_echo ""
    success_echo "报告已生成：$report_dir"
    warm_echo ""
    note_echo "推荐先看动态 HTML：$html_file"
  }

  # ✅ 主流程：显示自述、读取目录、准备环境、生成报告、打开结果。
  main() {
    : > "$LOG_FILE"

    print_readme

    local target_dir=""
    local report_dir=""
    local generator=""

    # 1. 最高优先级：先检测脚本所在目录和上一层目录是否包含 Podfile。
    # 2. 自动检测失败时，再进入手动拖入目录流程。
    if ! detect_target_dir_from_script_location; then
      prompt_target_dir
    fi
    target_dir="$SELECTED_TARGET_DIR"

    ensure_graphviz

    report_dir="$(prepare_report_dir "$target_dir")"
    generator="$report_dir/.generate_podspec_dependency_report.rb"

    write_generator_script "$generator"
    run_generator "$generator" "$target_dir" "$report_dir"
    generate_graphviz_png "$report_dir"
    open_outputs "$report_dir"
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
