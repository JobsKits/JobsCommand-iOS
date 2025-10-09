#!/bin/zsh
# ================================================================
# 🧩 iOS WebClip .mobileconfig 自动生成脚本（macOS 原生版）
# ---------------------------------------------------------------
# 功能：
# 1. 生成 iOS 桌面快捷方式（WebClip）配置文件。
# 2. 支持拖入图片、自动缩放并转 base64。
# 3. 输出文件 webclip.mobileconfig 到桌面。
# ---------------------------------------------------------------
# 作者：JobsHi（macOS 原生脚本封装示例）
# ================================================================

set -u  # 禁止未定义变量；不启用 -e 以便自定义错误处理

# ============================== 自述 ==============================
show_intro() {
cat <<'EOF'
🌈 ===============================================
              iOS WebClip 自动生成工具
===============================================
📘 功能说明：
  • 自动生成 iPhone/iPad 桌面快捷方式配置文件（.mobileconfig）
  • 使用系统自带工具，无需 Python、Pillow 或 Xcode。
  • 图标自动缩放为 64×64 并内嵌为 Base64。
-----------------------------------------------
⚙️ 使用步骤：
  1. 输入网页地址（URL）
  2. 输入桌面显示名称（Label）
  3. 拖入图标文件（PNG/JPG）
  4. 自动输出：~/Desktop/webclip.mobileconfig
===============================================
EOF
read "?👉 按回车键继续 ..."
}

# ============================== 工具检测 ==============================
check_dependencies() {
    for cmd in sips base64 uuidgen; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "❌ 缺少依赖：$cmd"
            read -n1 -s -r -p "按任意键退出…"
            exit 1
        fi
    done
}

# ============================== 图标验证与转换 ==============================
clean_path() {
    local raw="$1"
    raw="${raw#\'}"; raw="${raw%\'}"
    raw="${raw#\"}"; raw="${raw%\"}"
    printf '%b' "${raw//\\/\\}"
}

is_image() {
    local p="$1"
    sips -g pixelWidth "$p" >/dev/null 2>&1 && return 0
    if command -v file >/dev/null 2>&1; then
        file -b --mime-type "$p" | grep -qi '^image/' && return 0
    fi
    return 1
}

prepare_icon() {
    local icon_path="$1"
    local tmp_icon="/tmp/webclip_icon_64.png"
    sips -z 64 64 "$icon_path" --out "$tmp_icon" >/dev/null 2>&1
    base64 -i "$tmp_icon"
}

# ============================== 核心生成逻辑 ==============================
generate_mobileconfig() {
    local url="$1"
    local label="$2"
    local icon_base64="$3"
    local output="$HOME/Desktop/webclip.mobileconfig"

    local uuid1=$(uuidgen | tr '[:lower:]' '[:upper:]')
    local uuid2=$(uuidgen | tr '[:lower:]' '[:upper:]')

    # 写入配置文件
    cat > "$output" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>FullScreen</key>
      <true/>
      <key>IsRemovable</key>
      <true/>
      <key>Label</key>
      <string>$label</string>
      <key>PayloadType</key>
      <string>com.apple.webClip.managed</string>
      <key>PayloadUUID</key>
      <string>$uuid1</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>Precomposed</key>
      <true/>
      <key>URL</key>
      <string>$url</string>
EOF

    if [[ -n "$icon_base64" ]]; then
        cat >> "$output" <<EOF
      <key>Icon</key>
      <data>
$icon_base64
      </data>
EOF
    fi

    cat >> "$output" <<EOF
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>Web Clip Profile</string>
  <key>PayloadIdentifier</key>
  <string>com.jobs.webclip</string>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>$uuid2</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

    echo "✅ 已生成：$output"
    open -R "$output"  # 打开 Finder 定位结果
}

# ============================== 主函数 ==============================
main() {
    show_intro
    check_dependencies

    echo
    read "?🌐 请输入网页地址 (例如 https://yourwebsite.com)： " url
    [[ -z "$url" ]] && echo "❌ URL 不能为空" && exit 1

    read "?🏷️ 请输入桌面显示名称： " label
    [[ -z "$label" ]] && echo "❌ 名称不能为空" && exit 1

    echo
    local icon_path=""
    while true; do
        echo "🖼️  请从 Finder 拖入图标文件（PNG/JPG），然后按回车："
        read -r USER_INPUT
        USER_INPUT="${USER_INPUT:-}"
        CLEANED="$(clean_path "$USER_INPUT")"

        if [[ -z "$CLEANED" ]]; then
            echo "⚠️  未检测到输入，请重试。"
            continue
        fi
        if [[ ! -f "$CLEANED" ]]; then
            echo "⚠️  文件不存在：$CLEANED"
            continue
        fi
        if ! is_image "$CLEANED"; then
            echo "⚠️  不是有效图片文件，请重新拖入。"
            continue
        fi
        icon_path="$CLEANED"
        break
    done

    echo "🪄  正在处理图标并生成配置文件..."
    icon_base64="$(prepare_icon "$icon_path")"
    generate_mobileconfig "$url" "$label" "$icon_base64"

    echo
    read -n1 -s -r -p "按任意键关闭窗口…"
}

main "$@"
