#!/usr/bin/env zsh
# ================================== iOS DeviceSupport 备份与恢复 ==================================
set -euo pipefail

# ========== 全局变量 ==========
XCODE_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport"
BACKUP_BASE="$HOME/Documents/Xcode_DeviceSupport_Backup"
LOG_FILE="/tmp/xcode_device_support.log"
mkdir -p "$BACKUP_BASE"

# ========== 输出函数 ==========
info_echo()    { echo "ℹ️  $*"; }
success_echo() { echo "✅ $*"; }
error_echo()   { echo "❌ $*"; }

# ================================== 模块：自述 ==================================
show_intro() {
  cat <<EOF
============================================================
📌 Xcode DeviceSupport 管理脚本
------------------------------------------------------------
1. 本脚本用于对 Xcode 的 DeviceSupport 文件夹进行：
   - 备份：保存当前 DeviceSupport 到 $BACKUP_BASE
   - 恢复：从 $BACKUP_BASE 中选择一个备份还原到 Xcode
2. 使用场景：
   - 误删 DeviceSupport，无法调试真机
   - 想要快速恢复到之前的版本
3. 风险提示：
   - 恢复会覆盖 Xcode 内的 DeviceSupport
   - 需要 sudo 权限
============================================================
EOF
}

# ================================== 模块：等待确认 ==================================
wait_for_enter() {
  echo
  read "REPLY?👉 按回车继续（Ctrl+C 退出）..."
}

# ================================== 模块：备份 DeviceSupport ==================================
backup_device_support() {
  TS=$(date +"%Y%m%d_%H%M%S")
  DEST="$BACKUP_BASE/DeviceSupport_$TS"
  info_echo "正在备份 $XCODE_PATH → $DEST ..."
  sudo cp -R "$XCODE_PATH" "$DEST"
  success_echo "备份完成: $DEST"
}

# ================================== 模块：恢复 DeviceSupport ==================================
restore_device_support() {
  echo "📂 可用备份："
  ls -1 "$BACKUP_BASE" || { error_echo "没有可用备份"; exit 1; }
  echo
  read "BK?请输入要恢复的备份文件夹名: "
  SRC="$BACKUP_BASE/$BK"
  if [[ ! -d "$SRC" ]]; then
    error_echo "未找到备份: $SRC"
    exit 1
  fi
  info_echo "正在恢复 $SRC → $XCODE_PATH ..."
  sudo rm -rf "$XCODE_PATH"
  sudo cp -R "$SRC" "$XCODE_PATH"
  sudo chown -R $(whoami):staff "$XCODE_PATH"
  success_echo "恢复完成 ✅ 请重启 Xcode"
}

# ================================== 模块：菜单选择 ==================================
show_menu() {
  echo
  echo "请选择操作："
  echo "1) 备份当前 DeviceSupport"
  echo "2) 恢复 DeviceSupport"
  echo
  read "CHOICE?请输入数字 (1/2): "
  case "$CHOICE" in
    1) backup_device_support ;;
    2) restore_device_support ;;
    *) error_echo "无效选择: $CHOICE"; exit 1 ;;
  esac
}

# ================================== 主函数 ==================================
main() {
  # 1. 打印自述
  show_intro
  # 2. 等待用户回车确认
  wait_for_enter
  # 3. 弹出菜单，选择备份或恢复
  show_menu
}

main "$@"
