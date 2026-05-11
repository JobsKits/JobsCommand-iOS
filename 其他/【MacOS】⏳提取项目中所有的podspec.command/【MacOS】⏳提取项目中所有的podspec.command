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

  RED='\033[31m'
  GREEN='\033[32m'
  YELLOW='\033[33m'
  BLUE='\033[34m'
  NC='\033[0m'

  PROJECT_PATH=''
  OUTPUT_DIR=''
  PODSPEC_COUNT=0
  PODFILE_COUNT=0
  TOTAL_COUNT=0
  COPIED_SOURCE_LIST=''

  print_intro() {
      printf "${BLUE}============================================================${NC}\n"
      printf "${BLUE} 提取项目中的 CocoaPods 相关文件${NC}\n"
      printf "${BLUE}============================================================${NC}\n"
      printf "\n"
      printf "功能说明：\n"
      printf "1. 从你拖入的 Xcode 工程目录中递归查找并复制所有 .podspec 文件。\n"
      printf "2. 只从你拖入的工程根目录复制 Podfile.deps、Podfile、Podfile.lock。\n"
      printf "3. Podfile.deps、Podfile、Podfile.lock 不会递归查找子目录，避免把 Pods、Example、Demo 里的 Podfile 全复制出来。\n"
      printf "4. 复制结果会放到桌面新建的 PodspecFiles_时间戳 文件夹中。\n"
      printf "5. 如果 Podfile.deps、Podfile、Podfile.lock 不存在，只会用红字提示，不会影响脚本继续执行。\n"
      printf "6. 如果出现同名文件，会自动追加 _1、_2 等序号，避免覆盖。\n"
      printf "7. 支持拖入 Finder 替身、软链接，会尽量解析到背后的真实目录。\n"
      printf "8. 支持 .podspec、Podfile.deps、Podfile、Podfile.lock 本身是 Finder 替身或软链接，会复制其真正指向的文件。\n"
      printf "9. 支持 Finder 默认生成的 podspec 替身文件名，例如 xxx.podspec 替身、xxx.podspec alias。\n"
      printf "\n"
      printf "${YELLOW}按回车开始执行...${NC}"
      read -r _
      printf "\n"
  }

  normalize_dragged_path() {
      local RAW_PATH="$1"

      # 去掉首尾空白
      RAW_PATH="$(echo "$RAW_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

      # 去掉首尾引号
      RAW_PATH="${RAW_PATH%\"}"
      RAW_PATH="${RAW_PATH#\"}"
      RAW_PATH="${RAW_PATH%\'}"
      RAW_PATH="${RAW_PATH#\'}"

      # 处理 macOS 终端拖入路径时的反斜杠转义，例如 My\ Project
      RAW_PATH="$(printf '%s\n' "$RAW_PATH" | sed 's/\\\(.\)/\1/g')"

      # 支持手动输入 ~/Desktop/xxx
      if [[ "$RAW_PATH" == "~" || "$RAW_PATH" == ~/* ]]; then
          RAW_PATH="${RAW_PATH/#\~/$HOME}"
      fi

      printf '%s\n' "$RAW_PATH"
  }

  canonicalize_path() {
      local INPUT_PATH="$1"
      local DIR_NAME
      local BASE_NAME

      if [ -d "$INPUT_PATH" ]; then
          (
              cd "$INPUT_PATH" 2>/dev/null && pwd -P
          ) || printf '%s\n' "$INPUT_PATH"
          return
      fi

      if [ -e "$INPUT_PATH" ] || [ -L "$INPUT_PATH" ]; then
          DIR_NAME="$(dirname "$INPUT_PATH")"
          BASE_NAME="$(basename "$INPUT_PATH")"
          (
              cd "$DIR_NAME" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$BASE_NAME"
          ) || printf '%s\n' "$INPUT_PATH"
          return
      fi

      printf '%s\n' "$INPUT_PATH"
  }

  resolve_unix_symlink_path() {
      local INPUT_PATH="$1"
      local LINK_TARGET
      local LINK_DIR

      if [ ! -L "$INPUT_PATH" ]; then
          printf '%s\n' "$INPUT_PATH"
          return
      fi

      LINK_TARGET="$(readlink "$INPUT_PATH" 2>/dev/null)"

      if [ -z "$LINK_TARGET" ]; then
          printf '%s\n' "$INPUT_PATH"
          return
      fi

      if [[ "$LINK_TARGET" != /* ]]; then
          LINK_DIR="$(dirname "$INPUT_PATH")"
          LINK_TARGET="$LINK_DIR/$LINK_TARGET"
      fi

      canonicalize_path "$LINK_TARGET"
  }

  resolve_finder_alias_path() {
      local INPUT_PATH="$1"
      local RESOLVED_PATH

      # Finder 的“替身”不是 Unix 软链接，readlink 解析不了。
      # 这里用 Finder 的 original item 解析替身背后的真实资源路径。
      RESOLVED_PATH="$(osascript - "$INPUT_PATH" <<'APPLESCRIPT' 2>/dev/null
  on run argv
      set inputPath to item 1 of argv
      try
          tell application "Finder"
              set inputItem to (POSIX file inputPath) as alias
              try
                  set originalItemPath to POSIX path of ((original item of inputItem) as alias)
                  return originalItemPath
              on error
                  return inputPath
              end try
          end tell
      on error
          return inputPath
      end try
  end run
  APPLESCRIPT
  )"

      if [ -n "$RESOLVED_PATH" ]; then
          printf '%s\n' "$RESOLVED_PATH"
      else
          printf '%s\n' "$INPUT_PATH"
      fi
  }

  resolve_real_path() {
      local INPUT_PATH="$1"
      local CURRENT_PATH
      local NEXT_PATH
      local INDEX

      CURRENT_PATH="$(canonicalize_path "$INPUT_PATH")"
      INDEX=0

      # 最多解析 10 层：软链接 -> Finder 替身 -> 软链接这种组合也能处理。
      while [ "$INDEX" -lt 10 ]; do
          NEXT_PATH="$(resolve_unix_symlink_path "$CURRENT_PATH")"
          NEXT_PATH="$(resolve_finder_alias_path "$NEXT_PATH")"
          NEXT_PATH="$(canonicalize_path "$NEXT_PATH")"

          if [ "$NEXT_PATH" = "$CURRENT_PATH" ]; then
              break
          fi

          CURRENT_PATH="$NEXT_PATH"
          INDEX=$((INDEX + 1))
      done

      printf '%s\n' "$CURRENT_PATH"
  }

  resolve_dragged_path() {
      resolve_real_path "$1"
  }

  read_project_path() {
      local RAW_PATH
      local NORMALIZED_PATH

      while true; do
          echo "请把 Xcode 工程目录拖到这里，然后按回车："
          read -r RAW_PATH

          NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"
          NORMALIZED_PATH="$(resolve_dragged_path "$NORMALIZED_PATH")"

          if [ -d "$NORMALIZED_PATH" ]; then
              PROJECT_PATH="$NORMALIZED_PATH"
              printf "${GREEN}已解析目录：%s${NC}\n" "$PROJECT_PATH"
              break
          fi

          echo ""
          printf "${RED}错误：路径不存在，或者不是文件夹：${NC}\n"
          echo "$NORMALIZED_PATH"
          echo "请重新输入。"
          echo ""
      done
  }

  create_output_dir() {
      local DESKTOP_DIR="$HOME/Desktop"
      local TIME_TEXT

      TIME_TEXT="$(date '+%Y%m%d_%H%M%S')"
      OUTPUT_DIR="$DESKTOP_DIR/PodspecFiles_$TIME_TEXT"

      mkdir -p "$OUTPUT_DIR"
  }

  create_copied_source_list() {
      COPIED_SOURCE_LIST="$(mktemp "/tmp/podspec_real_sources.XXXXXX")"
  }

  cleanup_temp_files() {
      if [ -n "$COPIED_SOURCE_LIST" ] && [ -f "$COPIED_SOURCE_LIST" ]; then
          rm -f "$COPIED_SOURCE_LIST"
      fi
  }

  is_podspec_path() {
      local INPUT_PATH="$1"
      local LOWER_PATH

      LOWER_PATH="$(printf '%s' "$INPUT_PATH" | tr '[:upper:]' '[:lower:]')"
      [[ "$LOWER_PATH" == *.podspec ]]
  }

  has_copied_source() {
      local REAL_SOURCE_FILE="$1"

      if [ ! -f "$COPIED_SOURCE_LIST" ]; then
          return 1
      fi

      grep -F -x -q -- "$REAL_SOURCE_FILE" "$COPIED_SOURCE_LIST"
  }

  record_copied_source() {
      local REAL_SOURCE_FILE="$1"

      printf '%s\n' "$REAL_SOURCE_FILE" >> "$COPIED_SOURCE_LIST"
  }

  make_unique_target_file() {
      local SOURCE_FILE="$1"
      local FILE_NAME
      local TARGET_FILE
      local NAME
      local EXT
      local INDEX

      FILE_NAME="$(basename "$SOURCE_FILE")"
      TARGET_FILE="$OUTPUT_DIR/$FILE_NAME"

      if [ ! -e "$TARGET_FILE" ]; then
          echo "$TARGET_FILE"
          return
      fi

      if [[ "$FILE_NAME" == *.* ]]; then
          NAME="${FILE_NAME%.*}"
          EXT=".${FILE_NAME##*.}"
      else
          NAME="$FILE_NAME"
          EXT=""
      fi

      INDEX=1

      while [ -e "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}" ]; do
          INDEX=$((INDEX + 1))
      done

      echo "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}"
  }

  copy_to_output_dir() {
      local SOURCE_FILE="$1"
      local REAL_SOURCE_FILE
      local TARGET_FILE

      REAL_SOURCE_FILE="$(resolve_real_path "$SOURCE_FILE")"

      if [ ! -f "$REAL_SOURCE_FILE" ]; then
          printf "${RED}跳过：目标不存在，或者目标不是文件：%s${NC}\n" "$SOURCE_FILE"
          if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
              printf "${RED}  指向：%s${NC}\n" "$REAL_SOURCE_FILE"
          fi
          return 1
      fi

      if has_copied_source "$REAL_SOURCE_FILE"; then
          if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
              printf "${YELLOW}跳过重复目标：%s -> %s${NC}\n" "$SOURCE_FILE" "$REAL_SOURCE_FILE"
          else
              printf "${YELLOW}跳过重复目标：%s${NC}\n" "$REAL_SOURCE_FILE"
          fi
          return 1
      fi

      TARGET_FILE="$(make_unique_target_file "$REAL_SOURCE_FILE")"

      cp -p "$REAL_SOURCE_FILE" "$TARGET_FILE"
      record_copied_source "$REAL_SOURCE_FILE"

      if [ "$REAL_SOURCE_FILE" != "$SOURCE_FILE" ]; then
          echo "已复制：$SOURCE_FILE -> $REAL_SOURCE_FILE"
      else
          echo "已复制：$REAL_SOURCE_FILE"
      fi

      TOTAL_COUNT=$((TOTAL_COUNT + 1))
      return 0
  }

  copy_podspec_files() {
      local PODSPEC_FILE

      while IFS= read -r -d '' PODSPEC_FILE; do
          if copy_to_output_dir "$PODSPEC_FILE"; then
              PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
          fi
      done < <(find "$PROJECT_PATH" \( -type f -o -type l \) -iname "*.podspec" -print0)
  }

  copy_podspec_alias_target_files() {
      local CANDIDATE_FILE
      local REAL_SOURCE_FILE

      # Finder 默认创建的替身通常会叫：xxx.podspec 替身 / xxx.podspec alias。
      # 这里补扫这些候选文件：只要它背后真正指向的是 .podspec，就复制真实目标文件。
      while IFS= read -r -d '' CANDIDATE_FILE; do
          REAL_SOURCE_FILE="$(resolve_real_path "$CANDIDATE_FILE")"

          if [ "$REAL_SOURCE_FILE" = "$CANDIDATE_FILE" ]; then
              continue
          fi

          if [ -f "$REAL_SOURCE_FILE" ] && is_podspec_path "$REAL_SOURCE_FILE"; then
              if copy_to_output_dir "$CANDIDATE_FILE"; then
                  PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
              fi
          fi
      done < <(find "$PROJECT_PATH" \( -type f -o -type l \) \( -iname "*podspec*" -o -iname "*alias*" -o -iname "*替身*" -o -iname "*别名*" \) ! -iname "*.podspec" -print0)
  }

  copy_root_podfile_by_name() {
      local PODFILE_NAME="$1"
      local PODFILE_FILE="$PROJECT_PATH/$PODFILE_NAME"
      local REAL_PODFILE_FILE

      if [ -e "$PODFILE_FILE" ] || [ -L "$PODFILE_FILE" ]; then
          REAL_PODFILE_FILE="$(resolve_real_path "$PODFILE_FILE")"

          if [ -f "$REAL_PODFILE_FILE" ]; then
              if copy_to_output_dir "$PODFILE_FILE"; then
                  PODFILE_COUNT=$((PODFILE_COUNT + 1))
              fi
          else
              printf "${RED}找到但目标不是文件：%s${NC}\n" "$PODFILE_NAME"
              printf "${RED}  指向：%s${NC}\n" "$REAL_PODFILE_FILE"
          fi
      else
          printf "${RED}未找到：%s${NC}\n" "$PODFILE_NAME"
      fi
  }

  copy_root_podfiles() {
      copy_root_podfile_by_name "Podfile.deps"
      copy_root_podfile_by_name "Podfile"
      copy_root_podfile_by_name "Podfile.lock"
  }

  remove_empty_output_dir_if_needed() {
      if [ "$TOTAL_COUNT" -eq 0 ]; then
          rmdir "$OUTPUT_DIR"
          printf "${RED}没有找到任何 .podspec、Podfile.deps、Podfile、Podfile.lock 文件。${NC}\n"
          exit 0
      fi
  }

  print_result() {
      echo ""
      printf "${GREEN}完成，共复制 %s 个文件。${NC}\n" "$TOTAL_COUNT"
      echo "其中 .podspec 文件：$PODSPEC_COUNT 个。"
      echo "其中 Podfile 相关文件：$PODFILE_COUNT 个。"
      echo "输出目录：$OUTPUT_DIR"
  }

  open_output_dir() {
      open "$OUTPUT_DIR"
  }

  make_unique_zip_file() {
      local ZIP_FILE="$OUTPUT_DIR.zip"
      local ZIP_DIR
      local ZIP_BASE
      local ZIP_NAME
      local INDEX

      if [ ! -e "$ZIP_FILE" ]; then
          echo "$ZIP_FILE"
          return
      fi

      ZIP_DIR="$(dirname "$ZIP_FILE")"
      ZIP_BASE="$(basename "$ZIP_FILE")"
      ZIP_NAME="${ZIP_BASE%.zip}"
      INDEX=1

      while [ -e "$ZIP_DIR/${ZIP_NAME}_${INDEX}.zip" ]; do
          INDEX=$((INDEX + 1))
      done

      echo "$ZIP_DIR/${ZIP_NAME}_${INDEX}.zip"
  }

  ask_zip_output_dir() {
      local USER_INPUT
      local ZIP_FILE

      echo ""
      printf "${YELLOW}是否需要打包成 zip？直接回车 = 打包，输入任意字符 = 结束退出：${NC}"
      read -r USER_INPUT

      if [ -n "$USER_INPUT" ]; then
          printf "${YELLOW}已结束，未打包 zip。${NC}
  "
          return 0
      fi

      ZIP_FILE="$(make_unique_zip_file)"

      if ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR" "$ZIP_FILE"; then
          printf "${GREEN}已打包 zip：%s${NC}
  " "$ZIP_FILE"
      else
          printf "${RED}打包 zip 失败。${NC}
  "
          return 1
      fi
  }

  main() {
      trap cleanup_temp_files EXIT

      # 1. 打印脚本自述，并等待用户确认开始。
      print_intro

      # 2. 读取并校验用户拖入的 Xcode 工程目录。
      read_project_path

      # 3. 在桌面创建本次导出的目标文件夹。
      create_output_dir
      create_copied_source_list

      # 4. 递归复制项目中的 .podspec 文件。
      copy_podspec_files

      # 5. 补充处理 Finder 默认命名的 podspec 替身文件。
      copy_podspec_alias_target_files

      # 6. 只从工程根目录复制 Podfile.deps、Podfile、Podfile.lock。
      copy_root_podfiles

      # 7. 如果什么都没复制到，则删除空目录并正常结束。
      remove_empty_output_dir_if_needed

      # 8. 打印统计结果，并打开输出目录。
      print_result
      open_output_dir

      # 9. 执行完毕后询问是否需要将输出目录打包成 zip。
      ask_zip_output_dir
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
