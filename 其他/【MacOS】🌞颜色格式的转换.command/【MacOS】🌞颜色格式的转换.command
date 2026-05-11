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
  # ================================== 自述 ==================================
  # 名称：万能颜色格式转换器（纯 Shell）
  # 功能：在 #RRGGBB / #RRGGBBAA / rgb() / rgba() / 0xAARRGGBB 之间互转 + 终端色块预览
  # 输出：#RRGGBB、#RRGGBBAA、rgb()、rgba()、0xAARRGGBB，并显示“原色”色块（不做叠白/叠黑）
  # 交互：
  #   - 无参数 → 进入交互模式（可多次输入，q 退出）
  #   - 有参数 → 逐个批量转换并输出
  # 依赖：bash/zsh + awk/sed/printf（无第三方）
  # =========================================================================

  # ================================== 全局配置 ==================================
  # 标题颜色: #D2D4DE (210,212,222)
  TITLE_R=210; TITLE_G=212; TITLE_B=222
  ESC=$'\033'
  RESET="${ESC}[0m"
  TITLE_FG_TRUECOLOR="${ESC}[38;2;${TITLE_R};${TITLE_G};${TITLE_B}m"
  TITLE_FG_FALLBACK="${ESC}[37m"

  supports_truecolor() {
    [[ "${COLORTERM:-}" == *truecolor* || "${COLORTERM:-}" == *24bit* ]]
  }

  TITLE_COLOR() {
    if supports_truecolor; then printf "%s" "$TITLE_FG_TRUECOLOR"; else printf "%s" "$TITLE_FG_FALLBACK"; fi
  }

  # ================================== 基础工具函数 ==================================
  to_hex() { printf "%02X" "$1"; }
  alpha_float_to_255() { awk 'BEGIN{v='"$1"'; if(v<0)v=0;if(v>1)v=1; printf("%d",(v*255)+0.5)}'; }
  alpha_255_to_float() { awk 'BEGIN{printf("%.2f",'"$1"'/255)}'; }
  sanitize_input() { echo "$1" | tr -d '[:space:]' | tr -d '"' | tr -d "'"; }
  upper_hex() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

  # 亮度（用于选择黑/白前景）
  rel_luma() { awk 'BEGIN{r='"$1"';g='"$2"';b='"$3"'; printf("%.0f",0.2126*r+0.7152*g+0.0722*b)}'; }
  pick_fg_code() { local l; l=$(rel_luma "$1" "$2" "$3"); if (( l > 186 )); then echo "30"; else echo "97"; fi; }

  # xterm-256 背景色计算（TrueColor 不可用时退化）
  rgb_to_ansi256() {
    local r=$1 g=$2 b=$3
    if (( r==g && g==b )); then
      if   (( r < 8 ));   then echo 16;  return
      elif (( r > 248 )); then echo 231; return
      else echo $(( 232 + ( (r-8) * 24 / 247 ) )); return
      fi
    fi
    local rc=$(( (r * 5) / 255 ))
    local gc=$(( (g * 5) / 255 ))
    local bc=$(( (b * 5) / 255 ))
    echo $(( 16 + 36*rc + 6*gc + bc ))
  }

  # 色块输出
  show_block() {
    local rr=$1 gg=$2 bb=$3 label=$4
    local fg; fg=$(pick_fg_code "$rr" "$gg" "$bb")
    if supports_truecolor; then
      printf "\e[48;2;%d;%d;%dm" "$rr" "$gg" "$bb"
    else
      local idx; idx=$(rgb_to_ansi256 "$rr" "$gg" "$bb")
      printf "\e[48;5;%sm" "$idx"
    fi
    printf "\e[%sm" "$fg"
    printf "  %-18s  " "$label"
    printf "\e[0m"
  }

  # ================================== 解析输入为 RGBA =============================
  parse_input() {
    local raw="$1" input
    input=$(sanitize_input "$raw")

    if [[ "$input" =~ ^0x[0-9a-fA-F]{8}$ ]]; then
      local hex="${input:2}"; hex=$(upper_hex "$hex")
      local aa=${hex:0:2} rr=${hex:2:2} gg=${hex:4:2} bb=${hex:6:2}
      r=$((16#$rr)); g=$((16#$gg)); b=$((16#$bb))
      aa_hex="$aa"; a_float=$(alpha_255_to_float $((16#$aa))); return 0
    fi
    if [[ "$input" =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]]; then
      local hex="${input:1}"; hex=$(upper_hex "$hex")
      local rr=${hex:0:2} gg=${hex:2:2} bb=${hex:4:2}
      r=$((16#$rr)); g=$((16#$gg)); b=$((16#$bb))
      if [[ ${#hex} -eq 8 ]]; then
        aa_hex=${hex:6:2}; a_float=$(alpha_255_to_float $((16#$aa_hex)))
      else
        aa_hex="FF"; a_float="1.00"
      fi; return 0
    fi
    if [[ "$input" =~ ^rgba?\( ]]; then
      local nums; nums=$(echo "$input" | sed -E 's/^rgba?\(|\)//g')
      IFS=',' read -r R G B A <<<"$nums"
      r=${R%%.*}; g=${G%%.*}; b=${B%%.*}
      [[ -z "$A" ]] && A="1"
      a_float=$(awk 'BEGIN{printf("%.2f",'"$A"')}')
      local A255; A255=$(alpha_float_to_255 "$a_float")
      aa_hex=$(to_hex "$A255"); return 0
    fi
    return 1
  }

  # ================================== 格式化输出（含色块） ========================
  format_and_print_all() {
    local RR=$(to_hex "$r") GG=$(to_hex "$g") BB=$(to_hex "$b") AA="$aa_hex"
    echo
    echo -e "${ESC}[1m输入：$user_input${RESET}"
    echo "----------------------------------------"
    echo "HEX（不透明）:  #${RR}${GG}${BB}"
    echo "HEX（含透明） :  #${RR}${GG}${BB}${AA}"
    echo "RGB           :  rgb(${r}, ${g}, ${b})"
    echo "RGBA          :  rgba(${r}, ${g}, ${b}, $(printf '%.2f' "$a_float"))"
    echo "0x 格式       :  0x${AA}${RR}${GG}${BB}"
    show_block "$r" "$g" "$b" "原色 #${RR}${GG}${BB}"
    echo; echo
  }

  # ================================== UI & 交互 ==================================
  print_title() {
    local c; c="$(TITLE_COLOR)"
    echo -e "${c}================== 颜色格式转换器 ==================${RESET}"
    echo -e "${c}支持：#RRGGBB / #RRGGBBAA / rgb() / rgba() / 0xAARRGGBB${RESET}"
    echo -e "${c}标题使用颜色：#D2D4DE（210,212,222）${RESET}"
    echo -e "${c}在线取色器：https://photokit.com/colors/color-picker/?lang=zh${RESET}"
    echo
  }

  preface_and_wait() {
    print_title
    echo "自述："
    echo " - 纯 Shell 实现，不依赖第三方。"
    echo " - 输出包含 HEX、RGBA、以及 0xAARRGGBB（Flutter/Dart 常用）。"
    echo " - 无参进入交互模式，输入 q 退出。"
    echo
    printf "按回车开始执行..."
    IFS= read -r _
  }

  interactive_loop() {
    while true; do
      echo
      printf "请输入颜色值（q 退出）： "
      IFS= read -r user_input
      [[ -z "$user_input" ]] && continue
      [[ "$user_input" == [Qq] ]] && { echo "✅ 已退出"; break; }
      if parse_input "$user_input"; then
        format_and_print_all
      else
        echo "❌ 无法识别：$user_input"
        echo "示例：#D2D4DE、#D2D4DE80、rgb(210,212,222)、rgba(210,212,222,0.5)、0x80D2D4DE"
      fi
    done
  }

  convert_once() {
    user_input="$1"
    if parse_input "$user_input"; then
      format_and_print_all
    else
      echo "❌ 无法识别：$user_input"
    fi
  }

  # ================================== main ==================================
  main() {
    preface_and_wait
    if [[ $# -ge 1 ]]; then
      for user_input in "$@"; do
        convert_once "$user_input"
      done
    else
      interactive_loop
    fi
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
