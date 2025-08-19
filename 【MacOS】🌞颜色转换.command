#!/usr/bin/env bash
# ================================== 自述 ==================================
# 名称：万能颜色格式转换器（纯 Shell）
# 功能：在 #RRGGBB / #RRGGBBAA / rgb() / rgba() / 0xAARRGGBB 之间互转
# 输出：#RRGGBB、#RRGGBBAA、rgb()、rgba()、0xAARRGGBB
# 交互：
#   - 无参数 → 进入交互模式（可多次输入，q 退出）
#   - 有参数 → 逐个批量转换并输出
# 依赖：仅用系统自带 bash/zsh + awk/sed/printf（无第三方）
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

# ================================== 解析输入为 RGBA =============================
# 输出（全局变量）：
#   r g b       : 0~255
#   a_float     : 0.00~1.00
#   aa_hex      : 两位十六进制 Alpha（关键：打印阶段直接用它，避免被二次换算）
parse_input() {
  local raw="$1" input
  input=$(sanitize_input "$raw")

  # 0xAARRGGBB
  if [[ "$input" =~ ^0x[0-9a-fA-F]{8}$ ]]; then
    local hex="${input:2}"; hex=$(upper_hex "$hex")
    local aa=${hex:0:2} rr=${hex:2:2} gg=${hex:4:2} bb=${hex:6:2}
    r=$((16#$rr)); g=$((16#$gg)); b=$((16#$bb))
    aa_hex="$aa"
    a_float=$(alpha_255_to_float $((16#$aa)))
    return 0
  fi

  # #RRGGBB / #RRGGBBAA
  if [[ "$input" =~ ^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$ ]]; then
    local hex="${input:1}"; hex=$(upper_hex "$hex")
    local rr=${hex:0:2} gg=${hex:2:2} bb=${hex:4:2}
    r=$((16#$rr)); g=$((16#$gg)); b=$((16#$bb))
    if [[ ${#hex} -eq 8 ]]; then
      aa_hex=${hex:6:2}
      a_float=$(alpha_255_to_float $((16#$aa_hex)))
    else
      aa_hex="FF"          # ✅ 无透明度 → 默认不透明
      a_float="1.00"
    fi
    return 0
  fi

  # rgb(...) / rgba(...)
  if [[ "$input" =~ ^rgba?\( ]]; then
    local nums; nums=$(echo "$input" | sed -E 's/rgba?\(|\)//g')
    IFS=',' read -r R G B A <<<"$nums"
    r=${R%%.*}; g=${G%%.*}; b=${B%%.*}
    [[ -z "$A" ]] && A="1"
    a_float=$(awk 'BEGIN{printf("%.2f",'"$A"')}')
    local A255; A255=$(alpha_float_to_255 "$a_float")
    aa_hex=$(to_hex "$A255")  # ✅ 直接得到两位十六进制 Alpha
    return 0
  fi

  return 1
}

# ================================== 格式化输出 ==================================
format_and_print_all() {
  local RR=$(to_hex "$r") GG=$(to_hex "$g") BB=$(to_hex "$b")
  local AA="$aa_hex"   # ✅ 直接使用解析阶段给定的 AA，避免误差

  echo
  echo -e "${ESC}[1m输入：$user_input${RESET}"
  echo "----------------------------------------"
  echo "HEX（不透明）:  #${RR}${GG}${BB}"
  echo "HEX（含透明） :  #${RR}${GG}${BB}${AA}"
  echo "RGB           :  rgb(${r}, ${g}, ${b})"
  echo "RGBA          :  rgba(${r}, ${g}, ${b}, $(printf '%.2f' "$a_float"))"
  echo "0x 格式       :  0x${AA}${RR}${GG}${BB}"
  echo
}

# ================================== UI & 交互 ==================================
print_title() {
  local c="$(TITLE_COLOR)"
  echo -e "${c}================== 颜色格式转换器 ==================${RESET}"
  echo -e "${c}支持：#RRGGBB / #RRGGBBAA / rgb() / rgba() / 0xAARRGGBB${RESET}"
  echo -e "${c}标题使用颜色：#D2D4DE（210,212,222）${RESET}"
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
  preface_and_wait  # 显示自述并等待用户回车

  if [[ $# -ge 1 ]]; then
    # 传入 1 个或多个参数：逐个转换
    for user_input in "$@"; do
      convert_once "$user_input"
    done
  else
    # 无参数：进入交互模式
    interactive_loop
  fi
}

main "$@"
