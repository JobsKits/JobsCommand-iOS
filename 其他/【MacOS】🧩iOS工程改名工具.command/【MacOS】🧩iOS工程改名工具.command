#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩iOS工程改名工具.command
# - 核心用途：交互选择 iOS 工程，支持原地改名或复制开版后改名，并可选执行 Pods 维护。
# - 影响范围：会修改目标工程内文本、文件名、目录名；复制开版模式会创建新工程副本。
# - 运行提示：运行后会先打印内置自述并等待确认；删除、安装依赖等高风险动作会单独确认。

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"

SOURCE_PROJECT_ROOT=""
PROJECT_ROOT=""
ORIGINAL_PROJECT_ROOT=""
OLD_PROJECT_NAME=""
NEW_PROJECT_NAME=""
WORK_MODE="inplace"
COPY_PARENT_DIR=""
COPIED_PROJECT_ROOT=""
BACKUP_ZIP_PATH=""
WORKSPACE_ALIAS_PATH=""
TEXT_CHANGED_COUNT=0
FILE_RENAMED_COUNT=0
DIR_RENAMED_COUNT=0
CLEANED_ITEM_COUNT=0
POD_INSTALL_RAN="否"
FAILED_COUNT=0
FAILURE_MESSAGES=()
RENAME_PATHS=()

# 判断当前终端是否适合彩色输出。
supports_color() {
  [[ -t 1 && -z "${NO_COLOR:-}" && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}
# 写入一行终端输出，并同步追加到日志文件。
log() {
  local message="$1"
  print -r -- "$message" | tee -a "$LOG_FILE"
}
# 使用指定颜色输出日志，不支持彩色时自动降级为纯文本。
color_log() {
  local color="$1"
  local message="$2"
  local reset=$'\033[0m'
  if supports_color; then
    log "${color}${message}${reset}"
  else
    log "$message"
  fi
}
# 输出普通绿色日志。
color_echo() {
  color_log $'\033[1;32m' "$1"
}
# 输出信息日志。
info_echo() {
  color_log $'\033[1;34m' "ℹ $1"
}
# 输出成功日志。
success_echo() {
  color_log $'\033[1;32m' "✔ $1"
}
# 输出警告日志。
warn_echo() {
  color_log $'\033[1;33m' "⚠ $1"
}
# 输出温馨提示日志。
warm_echo() {
  color_log $'\033[1;33m' "$1"
}
# 输出说明日志。
note_echo() {
  color_log $'\033[1;35m' "➤ $1"
}
# 输出错误日志。
error_echo() {
  color_log $'\033[1;31m' "✖ $1"
}
# 输出错误纯文本日志。
err_echo() {
  color_log $'\033[1;31m' "$1"
}
# 输出调试日志。
debug_echo() {
  color_log $'\033[1;35m' "🐞 $1"
}
# 输出高亮日志。
highlight_echo() {
  color_log $'\033[1;36m' "🔹 $1"
}
# 输出次要信息日志。
gray_echo() {
  color_log $'\033[0;90m' "$1"
}
# 输出加粗日志。
bold_echo() {
  color_log $'\033[1m' "$1"
}
# 输出下划线日志。
underline_echo() {
  color_log $'\033[4m' "$1"
}
# 初始化本次运行日志文件。
prepare_runtime_log() {
  : > "$LOG_FILE"
}
# 在完整终端中清屏，避免瘦身终端出现 TERM 报错。
clear_screen_if_possible() {
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi
}
# 打印脚本内置自述，并等待用户确认后继续。
show_script_intro_and_wait() {
  prepare_runtime_log
  clear_screen_if_possible
  highlight_echo "══════════════════════════════ 脚本自述 ══════════════════════════════"
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：iOS 工程改名；支持原地改名，也支持复制新副本后开版改名。"
  warn_echo "影响范围：会修改目标工程内文本、文件名、目录名，必要时重命名工程根目录。"
  warn_echo "开版模块：复制副本、清 Pods / lock / workspace、pod install、workspace 快捷方式均为可选。"
  warn_echo "跳过目录：.git、Pods、node_modules、.dart_tool、build、DerivedData。"
  gray_echo "备份策略：直接回车跳过；输入任意字符后回车会先打包 zip。"
  gray_echo "危险策略：删除类维护动作必须输入 YES 才会执行。"
  gray_echo "日志位置：${LOG_FILE}"
  gray_echo "取消方式：确认前或真实改名前按 Ctrl+C 终止。"
  highlight_echo "═════════════════════════════════════════════════════════════════════"
  echo ""
  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，请在终端中双击或手动运行本脚本。"
    exit 1
  fi
  read -r "_?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消："
}
# 初始化 zsh 运行选项。
configure_shell_runtime() {
  setopt NO_NOMATCH
}
# 检查脚本依赖的 macOS 基础命令是否存在。
check_environment() {
  local missing_count=0
  local command_name=""
  local -a required_commands=(basename date dirname ditto find grep head ln mkdir mv osascript perl rm rsync sed sort tee)
  for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      error_echo "缺少必要命令：${command_name}"
      missing_count=$((missing_count + 1))
    fi
  done
  if [[ "$missing_count" -gt 0 ]]; then
    error_echo "环境检查未通过，请补齐上面的系统命令后重试。"
    exit 1
  fi
  success_echo "环境检查通过"
}
# 去掉字符串首尾空白。
trim_text() {
  print -r -- "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
# 展开用户输入路径中的家目录符号。
expand_home_path() {
  local value="$1"
  if [[ "$value" == "~" ]]; then
    print -r -- "$HOME"
  elif [[ "$value" == "~/"* ]]; then
    print -r -- "${HOME}/${value#~/}"
  else
    print -r -- "$value"
  fi
}
# 从用户拖入或输入的内容中解析第一个路径。
normalize_dragged_input() {
  local raw_value="$1"
  local trimmed_value=""
  local first_path=""
  local -a path_parts=()
  raw_value="${raw_value%$'\r'}"
  raw_value="${raw_value%$'\n'}"
  trimmed_value="$(trim_text "$raw_value")"
  if [[ -z "$trimmed_value" ]]; then
    print -r -- ""
    return 0
  fi
  path_parts=("${(z)trimmed_value}")
  if [[ "${#path_parts[@]}" -gt 1 ]]; then
    warn_echo "检测到多个路径，本次只使用第一个路径：${(Q)path_parts[1]}"
  fi
  first_path="${(Q)path_parts[1]}"
  expand_home_path "$first_path"
}
# 将已存在路径规范化为真实绝对路径。
canonicalize_existing_path() {
  local input_path="$1"
  local dir_name=""
  local base_name=""
  if [[ -z "$input_path" ]]; then
    print -r -- ""
    return 0
  fi
  if [[ -d "$input_path" ]]; then
    (cd "$input_path" 2>/dev/null && pwd -P) || print -r -- "$input_path"
    return 0
  fi
  if [[ -e "$input_path" || -L "$input_path" ]]; then
    dir_name="$(dirname "$input_path")"
    base_name="$(basename "$input_path")"
    (cd "$dir_name" 2>/dev/null && print -r -- "$(pwd -P)/${base_name}") || print -r -- "$input_path"
    return 0
  fi
  print -r -- "$input_path"
}
# 解析 Unix 软链接路径。
resolve_unix_symlink_path() {
  local input_path="$1"
  local link_target=""
  local link_dir=""
  if [[ -z "$input_path" || ! -L "$input_path" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  link_target="$(readlink "$input_path" 2>/dev/null || true)"
  if [[ -z "$link_target" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  if [[ "$link_target" != /* ]]; then
    link_dir="$(dirname "$input_path")"
    link_target="${link_dir}/${link_target}"
  fi
  canonicalize_existing_path "$link_target"
}
# 解析 Finder 替身路径，解析失败时保持原路径。
resolve_finder_alias_path() {
  local input_path="$1"
  local resolved_path=""
  if [[ -z "$input_path" || ! -e "$input_path" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  resolved_path="$(osascript - "$input_path" <<'APPLESCRIPT' 2>/dev/null
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
  if [[ -n "$resolved_path" ]]; then
    print -r -- "$resolved_path"
  else
    print -r -- "$input_path"
  fi
}
# 连续解析软链接和 Finder 替身，最多解析十层。
resolve_real_path() {
  local input_path="$1"
  local current_path=""
  local next_path=""
  local index=0
  current_path="$(canonicalize_existing_path "$input_path")"
  while [[ "$index" -lt 10 ]]; do
    next_path="$(resolve_unix_symlink_path "$current_path")"
    next_path="$(resolve_finder_alias_path "$next_path")"
    next_path="$(canonicalize_existing_path "$next_path")"
    if [[ "$next_path" == "$current_path" ]]; then
      break
    fi
    current_path="$next_path"
    index=$((index + 1))
  done
  print -r -- "$current_path"
}
# 如果用户拖入工程文件或配置文件，则回退到其父目录作为工程根目录。
coerce_project_root() {
  local input_path="$1"
  local base_name=""
  if [[ -z "$input_path" ]]; then
    print -r -- ""
    return 0
  fi
  base_name="$(basename "$input_path")"
  if [[ -d "$input_path" && ( "$base_name" == *.xcodeproj || "$base_name" == *.xcworkspace ) ]]; then
    canonicalize_existing_path "$(dirname "$input_path")"
    return 0
  fi
  if [[ -f "$input_path" ]]; then
    case "$base_name" in
      Package.swift|Podfile|Podfile.lock|*.podspec)
        canonicalize_existing_path "$(dirname "$input_path")"
        return 0
        ;;
    esac
  fi
  print -r -- "$input_path"
}
# 判断目录是否具备 iOS / Xcode / Pod / SPM 工程特征。
is_valid_ios_project_root() {
  local project_root="$1"
  local marker_path=""
  if [[ -z "$project_root" || ! -d "$project_root" ]]; then
    return 1
  fi
  marker_path="$(find "$project_root" -maxdepth 2 \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Package.swift" -o -name "Podfile" -o -name "*.podspec" \) -print -quit 2>/dev/null)"
  [[ -n "$marker_path" ]]
}
# 打印当前识别到的工程特征文件，方便用户确认。
print_project_markers() {
  local project_root="$1"
  local marker_path=""
  local display_path=""
  local shown_count=0
  note_echo "已识别到的工程特征："
  while IFS= read -r marker_path; do
    shown_count=$((shown_count + 1))
    [[ "$shown_count" -gt 8 ]] && break
    display_path="${marker_path#${project_root}/}"
    [[ "$display_path" == "$marker_path" ]] && display_path="."
    gray_echo "  - ${display_path}"
  done < <(find "$project_root" -maxdepth 2 \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Package.swift" -o -name "Podfile" -o -name "*.podspec" \) -print 2>/dev/null)
}
# 循环要求用户输入正确的 iOS 工程目录。
request_project_root_until_valid() {
  local raw_input=""
  local normalized_path=""
  local resolved_path=""
  local candidate_root=""
  while true; do
    echo ""
    note_echo "请把 iOS 工程目录拖到这里，或手动输入工程目录路径。"
    gray_echo "支持 .xcodeproj / .xcworkspace / Package.swift / Podfile / *.podspec 所在目录。"
    IFS= read -r "raw_input?➤ 工程路径："
    normalized_path="$(normalize_dragged_input "$raw_input")"
    resolved_path="$(resolve_real_path "$normalized_path")"
    candidate_root="$(coerce_project_root "$resolved_path")"
    candidate_root="$(canonicalize_existing_path "$candidate_root")"
    if is_valid_ios_project_root "$candidate_root"; then
      SOURCE_PROJECT_ROOT="$candidate_root"
      PROJECT_ROOT="$candidate_root"
      ORIGINAL_PROJECT_ROOT="$candidate_root"
      success_echo "工程目录确认：${PROJECT_ROOT}"
      print_project_markers "$PROJECT_ROOT"
      break
    fi
    warn_echo "输入未通过 iOS 工程检测，请重新输入正确工程目录。"
    gray_echo "统一判定：空白、路径不存在、不是目录、目录内没有工程特征，都会回到本步骤继续询问。"
  done
}
# 从工程标记文件中推断当前旧工程名。
detect_old_project_name() {
  local marker_path=""
  local package_name=""
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcodeproj" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .xcodeproj)"
    return 0
  fi
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .xcworkspace)"
    return 0
  fi
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.podspec" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .podspec)"
    return 0
  fi
  if [[ -f "${PROJECT_ROOT}/Package.swift" ]]; then
    package_name="$(grep -E '^[[:space:]]*name:[[:space:]]*"[^"]+"' "${PROJECT_ROOT}/Package.swift" 2>/dev/null | head -1 | sed -E 's/.*name:[[:space:]]*"([^"]+)".*/\1/')"
    if [[ -n "$package_name" ]]; then
      OLD_PROJECT_NAME="$package_name"
      return 0
    fi
  fi
  OLD_PROJECT_NAME="$(basename "$PROJECT_ROOT")"
}
# 判断工程名是否适合作为文件名和替换关键字。
is_valid_project_name() {
  local project_name="$1"
  project_name="$(trim_text "$project_name")"
  [[ -n "$project_name" && "$project_name" != "." && "$project_name" != ".." && "$project_name" != *"/"* && "$project_name" != *":"* ]]
}
# 允许用户修正脚本自动推断的旧工程名。
request_old_project_name_override() {
  local answer=""
  while true; do
    echo ""
    note_echo "检测到当前旧工程名：${OLD_PROJECT_NAME}"
    IFS= read -r "answer?➤ 直接回车沿用；如果检测不准，请输入旧工程名："
    answer="$(trim_text "$answer")"
    if [[ -z "$answer" ]]; then
      if is_valid_project_name "$OLD_PROJECT_NAME"; then
        success_echo "旧工程名确认：${OLD_PROJECT_NAME}"
        return 0
      fi
      warn_echo "自动推断的旧工程名不可用，请手动输入。"
    elif is_valid_project_name "$answer"; then
      OLD_PROJECT_NAME="$answer"
      success_echo "旧工程名确认：${OLD_PROJECT_NAME}"
      return 0
    else
      warn_echo "工程名不能为空，也不能包含 / 或 :，请重新输入。"
    fi
  done
}
# 循环要求用户输入新的工程项目名。
request_new_project_name_until_valid() {
  local answer=""
  while true; do
    echo ""
    note_echo "请输入要改成的新工程项目名。"
    gray_echo "示例：JobsApp / JobsSwiftDemo / JobsOCBaseConfigDemo"
    IFS= read -r "answer?➤ 新工程名："
    answer="$(trim_text "$answer")"
    if ! is_valid_project_name "$answer"; then
      warn_echo "新工程名不能为空，也不能包含 / 或 :，请重新输入。"
      continue
    fi
    if [[ "$answer" == "$OLD_PROJECT_NAME" ]]; then
      warn_echo "新工程名和旧工程名相同，没有改名意义，请重新输入。"
      continue
    fi
    NEW_PROJECT_NAME="$answer"
    success_echo "新工程名确认：${NEW_PROJECT_NAME}"
    break
  done
}
# 询问用户选择原地改名还是复制开版。
request_work_mode() {
  local answer=""
  while true; do
    echo ""
    note_echo "请选择运行模式。"
    gray_echo "1：原地改名，直接修改你拖入的工程目录。"
    gray_echo "2：复制开版，先复制工程副本到指定目录，再对副本改名。"
    IFS= read -r "answer?➤ 运行模式（直接回车=1）：" 
    answer="$(trim_text "$answer")"
    case "$answer" in
      ""|1)
        WORK_MODE="inplace"
        success_echo "运行模式：原地改名"
        return 0
        ;;
      2)
        WORK_MODE="copy"
        success_echo "运行模式：复制开版"
        return 0
        ;;
      *)
        warn_echo "请输入 1 / 2，或直接回车使用原地改名。"
        ;;
    esac
  done
}
# 收集工程目录、旧工程名、新工程名和运行模式。
collect_user_inputs() {
  request_project_root_until_valid
  detect_old_project_name
  request_old_project_name_override
  request_new_project_name_until_valid
  request_work_mode
}
# 询问用户是否执行普通可选动作。
ask_any_to_run() {
  local message="$1"
  local answer=""
  IFS= read -r "answer?${message}（直接回车跳过；输入任意字符后回车执行）："
  [[ -n "$answer" ]]
}
# 危险动作必须输入 YES 才允许继续。
confirm_yes() {
  local message="$1"
  local answer=""
  echo ""
  warn_echo "$message"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  IFS= read -r "answer?➤ "
  [[ "$answer" == "YES" ]]
}
# 询问复制开版的父目录并确认目标目录不存在。
request_copy_parent_until_valid() {
  local raw_input=""
  local normalized_path=""
  local resolved_path=""
  local target_path=""
  while true; do
    echo ""
    note_echo "请输入复制开版的父目录。"
    gray_echo "直接回车使用桌面：${HOME}/Desktop"
    IFS= read -r "raw_input?➤ 开版父目录："
    raw_input="$(trim_text "$raw_input")"
    if [[ -z "$raw_input" ]]; then
      resolved_path="${HOME}/Desktop"
    else
      normalized_path="$(normalize_dragged_input "$raw_input")"
      resolved_path="$(resolve_real_path "$normalized_path")"
    fi
    resolved_path="$(canonicalize_existing_path "$resolved_path")"
    if [[ ! -d "$resolved_path" ]]; then
      warn_echo "父目录不存在或不是目录，请重新输入。"
      continue
    fi
    target_path="${resolved_path}/${NEW_PROJECT_NAME}"
    if [[ -e "$target_path" || -L "$target_path" ]]; then
      warn_echo "开版目标已存在，避免覆盖：${target_path}"
      continue
    fi
    COPY_PARENT_DIR="$resolved_path"
    COPIED_PROJECT_ROOT="$target_path"
    success_echo "开版目标确认：${COPIED_PROJECT_ROOT}"
    return 0
  done
}
# 复制工程到新的开版目录，并默认排除 .git。
copy_project_for_opening() {
  note_echo "开始复制工程副本，默认排除 .git：${SOURCE_PROJECT_ROOT} -> ${COPIED_PROJECT_ROOT}"
  if mkdir -p "$COPIED_PROJECT_ROOT" && rsync -a --exclude ".git" "${SOURCE_PROJECT_ROOT}/" "${COPIED_PROJECT_ROOT}/"; then
    PROJECT_ROOT="$COPIED_PROJECT_ROOT"
    ORIGINAL_PROJECT_ROOT="$COPIED_PROJECT_ROOT"
    success_echo "工程副本已创建：${PROJECT_ROOT}"
  else
    error_echo "复制开版失败，已终止。"
    exit 1
  fi
}
# 根据运行模式准备真正要改名的工程目录。
prepare_project_workspace() {
  if [[ "$WORK_MODE" == "copy" ]]; then
    request_copy_parent_until_valid
    copy_project_for_opening
  else
    gray_echo "原地改名模式：将直接处理 ${PROJECT_ROOT}"
  fi
}
# 创建工程 zip 备份，失败时终止后续改名。
create_project_backup() {
  local parent_dir=""
  local timestamp=""
  local zip_name=""
  parent_dir="$(dirname "$PROJECT_ROOT")"
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  zip_name="${OLD_PROJECT_NAME}_rename_backup_${timestamp}.zip"
  BACKUP_ZIP_PATH="${parent_dir}/${zip_name}"
  note_echo "开始创建备份：${BACKUP_ZIP_PATH}"
  if ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT" "$BACKUP_ZIP_PATH"; then
    success_echo "备份完成：${BACKUP_ZIP_PATH}"
  else
    error_echo "备份失败，已终止改名，避免无备份继续修改工程。"
    exit 1
  fi
}
# 根据用户输入决定是否先备份工程。
ask_backup_and_run_if_needed() {
  echo ""
  if ask_any_to_run "👉 是否先把当前待改工程打包成 zip 备份"; then
    create_project_backup
  else
    warn_echo "已跳过 zip 备份；后续会直接修改当前待改工程。"
  fi
}
# 记录单项失败信息并增加失败计数。
record_failure() {
  local message="$1"
  FAILED_COUNT=$((FAILED_COUNT + 1))
  FAILURE_MESSAGES+=("$message")
  error_echo "$message"
}
# 判断路径是否属于默认跳过目录。
is_ignored_path() {
  local path_value="$1"
  [[ "$path_value" == */.git || "$path_value" == */.git/* ]] && return 0
  [[ "$path_value" == */Pods || "$path_value" == */Pods/* ]] && return 0
  [[ "$path_value" == */node_modules || "$path_value" == */node_modules/* ]] && return 0
  [[ "$path_value" == */.dart_tool || "$path_value" == */.dart_tool/* ]] && return 0
  [[ "$path_value" == */build || "$path_value" == */build/* ]] && return 0
  [[ "$path_value" == */DerivedData || "$path_value" == */DerivedData/* ]] && return 0
  return 1
}
# 判断文件是否可以按文本方式安全替换。
is_text_file() {
  local file_path="$1"
  [[ -f "$file_path" && -s "$file_path" ]] || return 1
  LC_ALL=C grep -Iq . "$file_path" 2>/dev/null
}
# 替换工程内文本文件中的旧工程名。
replace_text_occurrences() {
  local file_path=""
  note_echo "开始替换文本内容..."
  while IFS= read -r -d '' file_path; do
    is_ignored_path "$file_path" && continue
    is_text_file "$file_path" || continue
    if LC_ALL=C grep -Fq -- "$OLD_PROJECT_NAME" "$file_path" 2>/dev/null; then
      if OLD_PROJECT_NAME="$OLD_PROJECT_NAME" NEW_PROJECT_NAME="$NEW_PROJECT_NAME" perl -0pi -e 's/\Q$ENV{OLD_PROJECT_NAME}\E/$ENV{NEW_PROJECT_NAME}/g' "$file_path"; then
        TEXT_CHANGED_COUNT=$((TEXT_CHANGED_COUNT + 1))
        gray_echo "已替换文本：${file_path}"
      else
        record_failure "文本替换失败：${file_path}"
      fi
    fi
  done < <(find "$PROJECT_ROOT" \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o -type f -print0 2>/dev/null)
}
# 收集需要改名的文件和目录路径。
collect_paths_for_rename() {
  local current_path=""
  local base_name=""
  RENAME_PATHS=()
  while IFS= read -r -d '' current_path; do
    [[ "$current_path" == "$PROJECT_ROOT" ]] && continue
    is_ignored_path "$current_path" && continue
    base_name="$(basename "$current_path")"
    if [[ "$base_name" == *"$OLD_PROJECT_NAME"* ]]; then
      RENAME_PATHS+=("$current_path")
    fi
  done < <(find "$PROJECT_ROOT" \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o -print0 2>/dev/null)
  RENAME_PATHS=("${(O)RENAME_PATHS[@]}")
}
# 重命名单个文件或目录路径。
rename_one_path() {
  local current_path="$1"
  local parent_dir=""
  local base_name=""
  local new_base_name=""
  local target_path=""
  [[ -e "$current_path" || -L "$current_path" ]] || return 0
  parent_dir="$(dirname "$current_path")"
  base_name="$(basename "$current_path")"
  new_base_name="${base_name//$OLD_PROJECT_NAME/$NEW_PROJECT_NAME}"
  [[ "$new_base_name" == "$base_name" ]] && return 0
  target_path="${parent_dir}/${new_base_name}"
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    record_failure "改名目标已存在，已跳过：${target_path}"
    return 0
  fi
  if mv "$current_path" "$target_path"; then
    if [[ -d "$target_path" ]]; then
      DIR_RENAMED_COUNT=$((DIR_RENAMED_COUNT + 1))
      gray_echo "已重命名目录：${current_path} -> ${target_path}"
    else
      FILE_RENAMED_COUNT=$((FILE_RENAMED_COUNT + 1))
      gray_echo "已重命名文件：${current_path} -> ${target_path}"
    fi
  else
    record_failure "路径改名失败：${current_path}"
  fi
}
# 按从深到浅的顺序重命名工程内部文件和目录。
rename_nested_paths() {
  local current_path=""
  note_echo "开始重命名工程内部文件和目录..."
  collect_paths_for_rename
  if [[ "${#RENAME_PATHS[@]}" -eq 0 ]]; then
    gray_echo "未发现需要重命名的内部文件或目录。"
    return 0
  fi
  for current_path in "${RENAME_PATHS[@]}"; do
    rename_one_path "$current_path"
  done
}
# 如果工程根目录名称包含旧工程名，则最后再重命名根目录。
rename_project_root_if_needed() {
  local parent_dir=""
  local root_base_name=""
  local new_root_base_name=""
  local new_root_path=""
  root_base_name="$(basename "$PROJECT_ROOT")"
  if [[ "$root_base_name" != *"$OLD_PROJECT_NAME"* ]]; then
    gray_echo "工程根目录名称不包含旧工程名，跳过根目录改名。"
    return 0
  fi
  parent_dir="$(dirname "$PROJECT_ROOT")"
  new_root_base_name="${root_base_name//$OLD_PROJECT_NAME/$NEW_PROJECT_NAME}"
  new_root_path="${parent_dir}/${new_root_base_name}"
  if [[ -e "$new_root_path" || -L "$new_root_path" ]]; then
    record_failure "工程根目录改名目标已存在，已跳过：${new_root_path}"
    return 0
  fi
  if mv "$PROJECT_ROOT" "$new_root_path"; then
    DIR_RENAMED_COUNT=$((DIR_RENAMED_COUNT + 1))
    success_echo "工程根目录已改名：${PROJECT_ROOT} -> ${new_root_path}"
    PROJECT_ROOT="$new_root_path"
  else
    record_failure "工程根目录改名失败：${PROJECT_ROOT}"
  fi
}
# 执行 iOS 工程改名的核心业务。
rename_ios_project() {
  replace_text_occurrences
  rename_nested_paths
  rename_project_root_if_needed
}
# 删除单个路径并统计清理数量。
remove_path_if_exists() {
  local target_path="$1"
  if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
    gray_echo "未发现需要清理：${target_path}"
    return 0
  fi
  if rm -R "$target_path"; then
    CLEANED_ITEM_COUNT=$((CLEANED_ITEM_COUNT + 1))
    success_echo "已清理：${target_path}"
  else
    record_failure "清理失败：${target_path}"
  fi
}
# 清理 CocoaPods 生成目录、锁文件和 workspace。
clean_pods_generated_artifacts() {
  local workspace_path=""
  remove_path_if_exists "${PROJECT_ROOT}/Pods"
  remove_path_if_exists "${PROJECT_ROOT}/Podfile.lock"
  while IFS= read -r -d '' workspace_path; do
    remove_path_if_exists "$workspace_path"
  done < <(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" -print0 2>/dev/null)
}
# 执行 pod install 并记录结果。
run_pod_install_if_possible() {
  if [[ ! -f "${PROJECT_ROOT}/Podfile" ]]; then
    warn_echo "当前工程根目录没有 Podfile，跳过 pod install。"
    return 0
  fi
  if ! command -v pod >/dev/null 2>&1; then
    record_failure "未检测到 pod 命令，无法执行 pod install。"
    return 0
  fi
  note_echo "开始执行 pod install：${PROJECT_ROOT}"
  if (cd "$PROJECT_ROOT" && pod install); then
    POD_INSTALL_RAN="是"
    success_echo "pod install 执行完成"
  else
    POD_INSTALL_RAN="失败"
    record_failure "pod install 执行失败：${PROJECT_ROOT}"
  fi
}
# 查找当前工程根目录下优先使用的 workspace。
find_primary_workspace() {
  local workspace_path=""
  workspace_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "${NEW_PROJECT_NAME}.xcworkspace" -print 2>/dev/null | sort | head -1)"
  if [[ -z "$workspace_path" ]]; then
    workspace_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" -print 2>/dev/null | sort | head -1)"
  fi
  print -r -- "$workspace_path"
}
# 在桌面创建 workspace 软链接快捷方式。
create_workspace_alias_on_desktop() {
  local workspace_path=""
  local alias_path=""
  workspace_path="$(find_primary_workspace)"
  if [[ -z "$workspace_path" || ! -e "$workspace_path" ]]; then
    warn_echo "未找到可创建快捷方式的 .xcworkspace。"
    return 0
  fi
  alias_path="${HOME}/Desktop/${NEW_PROJECT_NAME}.xcworkspace"
  if [[ -e "$alias_path" || -L "$alias_path" ]]; then
    record_failure "桌面快捷方式目标已存在，已跳过：${alias_path}"
    return 0
  fi
  if ln -s "$workspace_path" "$alias_path"; then
    WORKSPACE_ALIAS_PATH="$alias_path"
    success_echo "已创建 workspace 快捷方式：${alias_path}"
  else
    record_failure "创建 workspace 快捷方式失败：${alias_path}"
  fi
}
# 改名完成后询问是否执行开版维护模块。
ask_opening_modules_and_run_if_needed() {
  echo ""
  if ! ask_any_to_run "👉 是否进入开版维护模块"; then
    warn_echo "已跳过开版维护模块。"
    return 0
  fi
  if confirm_yes "是否删除 Pods、Podfile.lock 和当前根目录下的 *.xcworkspace？"; then
    clean_pods_generated_artifacts
  else
    warn_echo "已跳过删除 Pods / lock / workspace。"
  fi
  echo ""
  if ask_any_to_run "👉 是否执行 pod install"; then
    run_pod_install_if_possible
  else
    warn_echo "已跳过 pod install。"
  fi
  echo ""
  if ask_any_to_run "👉 是否在桌面创建 .xcworkspace 快捷方式"; then
    create_workspace_alias_on_desktop
  else
    warn_echo "已跳过 workspace 快捷方式。"
  fi
}
# 输出失败列表，便于根据日志继续排查。
print_failures_if_needed() {
  local message=""
  if [[ "$FAILED_COUNT" -le 0 ]]; then
    return 0
  fi
  warn_echo "失败明细如下："
  for message in "${FAILURE_MESSAGES[@]}"; do
    err_echo "  - ${message}"
  done
}
# 输出本次运行摘要并按失败状态返回。
show_summary() {
  echo ""
  highlight_echo "══════════════════════════════ 执行摘要 ══════════════════════════════"
  note_echo "运行模式：${WORK_MODE}"
  note_echo "源工程目录：${SOURCE_PROJECT_ROOT}"
  note_echo "旧工程名：${OLD_PROJECT_NAME}"
  note_echo "新工程名：${NEW_PROJECT_NAME}"
  note_echo "当前工程目录：${PROJECT_ROOT}"
  if [[ -n "$COPIED_PROJECT_ROOT" ]]; then
    gray_echo "开版副本目录：${COPIED_PROJECT_ROOT}"
  fi
  gray_echo "文本替换文件数：${TEXT_CHANGED_COUNT}"
  gray_echo "重命名文件数：${FILE_RENAMED_COUNT}"
  gray_echo "重命名目录数：${DIR_RENAMED_COUNT}"
  gray_echo "开版清理项数：${CLEANED_ITEM_COUNT}"
  gray_echo "pod install：${POD_INSTALL_RAN}"
  if [[ -n "$WORKSPACE_ALIAS_PATH" ]]; then
    gray_echo "workspace 快捷方式：${WORKSPACE_ALIAS_PATH}"
  fi
  if [[ -n "$BACKUP_ZIP_PATH" ]]; then
    gray_echo "备份文件：${BACKUP_ZIP_PATH}"
  else
    warn_echo "备份文件：未创建"
  fi
  gray_echo "日志文件：${LOG_FILE}"
  print_failures_if_needed
  highlight_echo "═════════════════════════════════════════════════════════════════════"
  if [[ "$FAILED_COUNT" -gt 0 ]]; then
    exit 1
  fi
  success_echo "iOS 工程改名 / 开版流程已完成"
}
# 编排脚本自述、环境检查和核心改名开版流程。
main() {
  show_script_intro_and_wait # 打印内置自述并等待确认，避免误触后直接修改工程。
  configure_shell_runtime # 初始化 zsh 运行选项，保证路径和通配符处理稳定。
  check_environment # 检查脚本依赖的 macOS 基础命令，缺失时提前终止。
  collect_user_inputs # 循环收集合法工程目录、旧工程名、新工程名和运行模式。
  prepare_project_workspace # 根据运行模式决定原地处理或先复制开版副本。
  ask_backup_and_run_if_needed # 询问是否创建 zip 备份，输入任意字符才执行备份。
  rename_ios_project # 执行文本替换、内部路径改名和工程根目录改名。
  ask_opening_modules_and_run_if_needed # 改名后按需执行清理 Pods、pod install 和 workspace 快捷方式。
  show_summary # 输出执行摘要、备份位置、日志位置和失败状态。
}

main "$@"
