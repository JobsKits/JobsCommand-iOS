#!/bin/zsh
# ===============================================================
#  scan_folder.command
# ---------------------------------------------------------------
#  功能：
#   • 递归扫描文件夹，统计每个目录文件数和总文件数。
#   • 支持拖入路径或命令行参数。
#   • 显示自述，用户按回车后执行。
# ---------------------------------------------------------------
#  作者：JobsHi
# ===============================================================

set -u  # 禁止未定义变量

# =========================== 输出函数 ===========================
info()    { echo "📘 $1"; }
success() { echo "✅ $1"; }
error()   { echo "❌ $1"; }

# =========================== 自述函数 ===========================
show_intro() {
  clear
  cat <<'EOF'
📦 ===========================================
              文件夹扫描统计工具
===========================================
📘 功能说明：
  • 自动统计目标文件夹及其子目录文件数量。
  • 支持拖入路径或直接传参。
  • 结果包含分级目录结构与总文件数。

⚙️ 使用方式：
  • 双击运行脚本后拖入文件夹路径并回车。
  • 或在终端执行：
      ./scan_folder.command /path/to/folder
===========================================
EOF
  read "?👉 按回车键继续执行 ..."
}

# =========================== 校验路径 ===========================
get_folder_path() {
  local folder_path=""
  if [[ -n "${1:-}" ]]; then
    folder_path="$1"
  else
    echo "📂 请拖入一个文件夹路径后回车："
    read folder_path
  fi
  if [[ ! -d "$folder_path" ]]; then
    error "路径无效或不是文件夹: $folder_path"
    exit 1
  fi
  echo "$folder_path"
}

# =========================== 递归扫描函数 ===========================
TOTAL_FILE_COUNT=0

scan_folder() {
  local folder="$1"
  local indent="$2"
  local subdirs=()
  local files=()

  for item in "$folder"/*; do
    [[ -e "$item" ]] || continue
    if [[ -d "$item" ]]; then
      subdirs+=("$item")
    elif [[ -f "$item" ]]; then
      files+=("$item")
    fi
  done

  local file_count=${#files[@]}
  echo "${indent}📁 $(basename "$folder") - $file_count 个文件"
  TOTAL_FILE_COUNT=$((TOTAL_FILE_COUNT + file_count))

  for subdir in "${subdirs[@]}"; do
    scan_folder "$subdir" "  $indent"
  done
}

# =========================== 主逻辑 ===========================
main() {
  show_intro
  local folder_path
  folder_path="$(get_folder_path "${1:-}")"

  echo
  info "📊 文件夹报告：$folder_path"
  echo "==========================="
  scan_folder "$folder_path" ""
  echo "==========================="
  success "📦 总文件数：$TOTAL_FILE_COUNT 个"
  echo
  read "?✅ 按回车退出 ..."
}

# =========================== 执行入口 ===========================
main "$@"
