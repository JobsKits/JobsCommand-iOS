#!/bin/zsh
# iOS_AppIcon_Generator.command
set -u  # 不用 -e，避免误退出；对关键命令我们手动判错

# ====================== 自述 ======================
clear
cat <<'EOF'
🌈 ===========================================
       iOS App Icon 自动生成工具
===========================================
📘 使用说明：
1. 准备一张方形源图（推荐 1024×1024 PNG/JPG）。
2. 按提示把图片从 Finder 拖入终端窗口后回车。
3. 程序会生成以下尺寸（像素）：
   20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024
4. 输出路径：桌面 AppIcon.appiconset/
5. 命名格式：Jobs{宽}x{高}.png（无 @2x/@3x 后缀）
===========================================
EOF
read "?👉 按回车键继续 ..."

# ====================== 基础配置 ======================
PREFIX="Jobs"
OUT_DIR="$HOME/Desktop/AppIcon.appiconset"
typeset -a SIZES=(20 29 40 58 60 76 80 87 120 152 167 180 1024)

# ====================== 依赖自检 ======================
if ! command -v sips >/dev/null 2>&1; then
  echo "❌ 未找到 macOS 自带的 sips，请检查系统。"; read -n1 -s -r -p "按任意键退出…"; exit 1
fi

# ====================== 工具函数 ======================
clean_path() {
  local raw="$1"
  raw="${raw#\'}"; raw="${raw%\'}"
  raw="${raw#\"}"; raw="${raw%\"}"
  # 还原反斜杠转义
  printf '%b' "${raw//\\/\\}"
}

resolve_alias_if_needed() {
  # 如果是 Finder “的替身”（Alias），解析到原始目标
  local p="$1"
  if command -v mdls >/dev/null 2>&1; then
    local kind
    kind=$(mdls -name kMDItemKind -raw "$p" 2>/dev/null || true)
    if echo "$kind" | grep -qi "alias"; then
      # 用 AppleScript 解析别名
      local resolved
      resolved=$(osascript -e 'on run argv
        set p to POSIX file (item 1 of argv)
        tell application "Finder"
          set t to original item of p as alias
          POSIX path of t
        end tell
      end run' "$p" 2>/dev/null || true)
      if [[ -n "$resolved" && -f "$resolved" ]]; then
        echo "$resolved"
        return 0
      fi
    fi
  fi
  echo "$p"
}

is_image() {
  # 返回 0 表示是图片；否则非图片
  local p="$1"

  # 先试 sips 探测像素（最快最准）
  local w
  w=$(sips -g pixelWidth "$p" 2>/dev/null | awk '/pixelWidth/{print $2}')
  if [[ "$w" =~ ^[0-9]+$ && "$w" -gt 0 ]]; then
    return 0
  fi

  # 再降级用 file MIME
  if command -v file >/dev/null 2>&1; then
    local mime
    mime=$(file -b --mime-type "$p" 2>/dev/null || true)
    if echo "$mime" | grep -qi '^image/'; then
      return 0
    fi
  fi

  # 再兜底看扩展名
  local ext="${p##*.}"; ext="${ext:l}"
  case "$ext" in
    png|jpg|jpeg|heic|webp|tif|tiff|bmp|gif|ico|icns) return 0 ;;
  esac

  return 1
}

prepare_square_png() {
  # 将任意图片转为 PNG，若非正方形则居中裁成正方形
  local in="$1" out_png="$2"

  # 转 PNG
  if ! sips -s format png "$in" --out "$out_png" >/dev/null 2>&1; then
    return 1
  fi

  local w h
  w=$(sips -g pixelWidth  "$out_png" 2>/dev/null | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$out_png" 2>/dev/null | awk '/pixelHeight/{print $2}')
  if [[ -z "$w" || -z "$h" || ! "$w" =~ ^[0-9]+$ || ! "$h" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  if [[ "$w" -ne "$h" ]]; then
    local s=$(( w < h ? w : h ))
    echo "📐 源图非正方形，裁剪为 ${s}x${s}"
    if ! sips -s format png -c "$s" "$s" "$out_png" --out "$out_png" >/dev/null 2>&1; then
      return 1
    fi
  fi
  return 0
}

# ====================== 主循环：反复要图片，直到正确 ======================
IMG_PATH=""
while true; do
  echo
  echo "👉 请从 Finder 拖入【图片文件】到此窗口，然后按回车："
  read -r USER_INPUT
  USER_INPUT="${USER_INPUT:-}"

  # 空输入
  if [[ -z "$USER_INPUT" ]]; then
    echo "⚠️  未检测到输入，请重试。"
    continue
  fi

  # 清洗路径并解析别名
  CLEANED="$(clean_path "$USER_INPUT")"
  TARGET="$(resolve_alias_if_needed "$CLEANED")"

  # 存在性检查
  if [[ ! -f "$TARGET" ]]; then
    echo "⚠️  文件不存在：$TARGET"
    continue
  fi

  # 图片性检查
  if ! is_image "$TARGET"; then
    echo "⚠️  这不是有效的图片文件：$TARGET"
    continue
  fi

  # 到这一步先做一次轻量探测，确保 sips 能处理
  if ! sips -g pixelWidth "$TARGET" >/dev/null 2>&1; then
    echo "⚠️  sips 无法读取该文件，请换一张图片。"
    continue
  fi

  IMG_PATH="$TARGET"
  break
done

# ====================== 生成流程 ======================
# 准备输出目录
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/tmp"

# 预处理：转 PNG + 正方形
SQ="$OUT_DIR/tmp/_square.png"
if ! prepare_square_png "$IMG_PATH" "$SQ"; then
  echo "❌ 图片预处理失败（格式转换/读取异常）。请重试。"
  read -n1 -s -r -p "按任意键退出…"; exit 1
fi

# 基准 1024（从大图缩放，避免多次缩放损失）
BASE="$OUT_DIR/tmp/_base_1024.png"
if ! sips -Z 1024 "$SQ" --out "$BASE" >/dev/null 2>&1; then
  echo "❌ 生成基准图失败。"; read -n1 -s -r -p "按任意键退出…"; exit 1
fi

echo
for px in "${SIZES[@]}"; do
  out="$OUT_DIR/${PREFIX}${px}x${px}.png"
  if sips -z "$px" "$px" "$BASE" --out "$out" >/dev/null 2>&1; then
    printf "✅ 生成 %-26s (%4d×%4d)\n" "$(basename "$out")" "$px" "$px"
  else
    printf "❌ 失败 %-26s\n" "$(basename "$out")"
  fi
done

# 清理
rm -rf "$OUT_DIR/tmp"

echo
echo "🎉 完成！输出路径：$OUT_DIR"
echo "👉 文件命名：${PREFIX}{宽}x{高}.png（无 @2x/@3x 后缀）"
echo
read -n 1 -s -r -p "按任意键关闭窗口…"
