#!/bin/bash
# ===============================================================
#  open_spm_checkouts.command
# ---------------------------------------------------------------
#  功能：
#   • 自动查找当前目录下的 .xcodeproj 项目
#   • 匹配 DerivedData 对应目录
#   • 打开 Swift Package 的 checkouts 文件夹
# ---------------------------------------------------------------
#  作者：JobsHi
#  用法：
#   • 将脚本放在项目根目录（与 .git 同级）
#   • 双击运行 或在终端执行 ./open_spm_checkouts.command
# ===============================================================

set -e  # 任意命令失败即退出

# =========================== 函数区 ===========================

# ---------- 切换到脚本所在目录 ----------
enter_script_dir() {
  cd "$(dirname "$0")"
}

# ---------- 查找 Xcode 项目名 ----------
find_project_name() {
  local project_file
  project_file=$(find . -maxdepth 1 -name "*.xcodeproj" | head -n 1)
  if [[ -z "$project_file" ]]; then
    echo "❌ 没有找到 .xcodeproj 文件"
    exit 1
  fi
  local project_name
  project_name=$(basename "$project_file" .xcodeproj)
  echo "$project_name"
}

# ---------- 获取 DerivedData 目录路径 ----------
get_derived_data_path() {
  local user_name
  user_name=$(whoami)
  echo "/Users/$user_name/Library/Developer/Xcode/DerivedData"
}

# ---------- 查找 DerivedData 下的项目目录 ----------
find_project_dir_in_derived_data() {
  local project_name="$1"
  local derived_data_dir="$2"
  local project_dir
  project_dir=$(find "$derived_data_dir" -type d -name "${project_name}-*" | head -n 1)
  if [[ -z "$project_dir" ]]; then
    echo "❌ 没有在 DerivedData 中找到项目目录"
    exit 1
  fi
  echo "$project_dir"
}

# ---------- 打开 Swift Package checkouts ----------
open_spm_checkouts() {
  local project_dir="$1"
  local spm_checkouts_dir="$project_dir/SourcePackages/checkouts"

  if [[ -d "$spm_checkouts_dir" ]]; then
    echo "✅ 打开 Swift Package 目录: $spm_checkouts_dir"
    open "$spm_checkouts_dir"
  else
    echo "❌ 没有找到 SourcePackages/checkouts 目录"
    exit 1
  fi
}

# =========================== 主函数 ===========================
main() {
  echo "🚀 开始查找 Swift Package checkouts 目录..."
  enter_script_dir

  # 获取项目名
  local project_name
  project_name=$(find_project_name)
  echo "📁 项目名: $project_name"

  # 获取 DerivedData 根目录
  local derived_data_dir
  derived_data_dir=$(get_derived_data_path)

  # 查找项目对应的 DerivedData 子目录
  local project_dir
  project_dir=$(find_project_dir_in_derived_data "$project_name" "$derived_data_dir")

  # 打开 Swift Package checkouts
  open_spm_checkouts "$project_dir"

  echo "🎉 操作完成"
}

# =========================== 执行入口 ===========================
main "$@"
