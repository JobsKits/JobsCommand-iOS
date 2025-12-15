#!/bin/zsh

# ✅ 日志与输出函数
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

# ✅ 自述信息
print_intro() {
    clear
    echo ""
    info_echo "🎬 本脚本用于录制 iOS 模拟器视频"
    echo "👉 流程如下："
    echo "1️⃣ 选择要启动的 iOS 模拟器（fzf）"
    echo "2️⃣ 自动关闭旧模拟器防止假后台"
    echo "3️⃣ 自动启动模拟器并录屏"
    echo "4️⃣ 再次回车停止录屏，然后可选是否转 GIF"
    echo "======================================="
    read "?📎 按回车继续..."
}

# ✅ 写入 Homebrew shellenv
inject_shellenv_block() {
    local profile_file="$1"   # 比如 ~/.zprofile
    local shellenv="$2"       # 比如 eval "$(/opt/homebrew/bin/brew shellenv)"
    local header="# >>> brew shellenv (auto) >>>"

    if [[ -z "$profile_file" || -z "$shellenv" ]]; then
        error_echo "❌ 缺少参数：inject_shellenv_block <profile_file> <shellenv>"
        return 1
    fi

    touch "$profile_file" 2>/dev/null || {
        error_echo "❌ 无法写入配置文件：$profile_file"
        return 1
    }

    if grep -Fq "$shellenv" "$profile_file" 2>/dev/null; then
        info_echo "📌 配置文件中已存在 brew shellenv：$profile_file"
    else
        {
            echo ""
            echo "$header"
            echo "$shellenv"
        } >> "$profile_file"
        success_echo "✅ 已写入 brew shellenv 到：$profile_file"
    fi

    eval "$shellenv"
    success_echo "🟢 Homebrew 环境已在当前终端生效"
}

# ✅ 判断芯片架构（ARM64 / x86_64）
get_cpu_arch() {
    [[ $(uname -m) == "arm64" ]] && echo "arm64" || echo "x86_64"
}

# ✅ 自检安装 Homebrew
install_homebrew() {
    local arch="$(get_cpu_arch)"            # 获取当前架构（arm64 或 x86_64）
    local shell_path="${SHELL##*/}"         # 获取当前 shell 名称（如 zsh、bash）
    local profile_file=""
    local brew_bin=""
    local shellenv_cmd=""

    if ! command -v brew &>/dev/null; then
        warn_echo "🧩 未检测到 Homebrew，正在安装中...（架构：$arch）"

        if [[ "$arch" == "arm64" ]]; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                error_echo "❌ Homebrew 安装失败（arm64）"
                exit 1
            }
            brew_bin="/opt/homebrew/bin/brew"
        else
            arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
                error_echo "❌ Homebrew 安装失败（x86_64）"
                exit 1
            }
            brew_bin="/usr/local/bin/brew"
        fi

        success_echo "✅ Homebrew 安装成功"

        # ==== 注入 shellenv 到对应配置文件（自动生效） ====
        shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""

        case "$shell_path" in
            zsh)   profile_file="$HOME/.zprofile" ;;
            bash)  profile_file="$HOME/.bash_profile" ;;
            *)     profile_file="$HOME/.profile" ;;
        esac

        inject_shellenv_block "$profile_file" "$shellenv_cmd"
    else
        info_echo "🔄 Homebrew 已安装，简单检查中..."
        brew -v || warn_echo "⚠️ brew -v 执行异常，稍后可自行排查"
    fi
}

# ✅ 自检安装 fzf（简化版）
install_fzf() {
    if ! command -v fzf &>/dev/null; then
        warn_echo "🧩 未检测到 fzf，正在通过 Homebrew 安装..."
        brew install fzf || {
            error_echo "❌ fzf 安装失败，请手动检查 Homebrew"
            return 1
        }
        success_echo "✅ fzf 安装完成"
    else
        info_echo "✅ fzf 已安装"
    fi
}

# ✅ 模拟器设备选择 📱
select_simulator_device() {
    info_echo "📱 正在获取可用 iOS 模拟器..."
    local devices
    devices=$(xcrun simctl list devices available | grep -E 'iPhone|iPad' | grep -v unavailable)
    [[ -z "$devices" ]] && { error_echo "❌ 无可用模拟器"; exit 1; }

    info_echo "📱 请选择一个 iOS 模拟器（fzf）："
    local selected
    selected=$(echo "$devices" | fzf --height=50% --border --prompt="选择模拟器：")
    [[ -z "$selected" ]] && { error_echo "❌ 未选择模拟器，操作已取消"; exit 1; }

    SIMULATOR_UDID=$(echo "$selected" | awk -F '[()]' '{print $2}')
    SIMULATOR_NAME=$(echo "$selected" | awk -F '[()]' '{print $1}' | sed 's/ *$//')
    success_echo "✅ 你选择的设备是：$SIMULATOR_NAME [$SIMULATOR_UDID]"
}

# ✅ 检查并关闭假后台模拟器 🧼
shutdown_fake_background_simulator() {
    info_echo "🧪 检查模拟器状态..."
    local booted running
    booted=$(xcrun simctl list devices | grep "(Booted)")
    running=$(pgrep -f Simulator || true)

    if [[ -z "$booted" && -n "$running" ]]; then
        warn_echo "⚠️ 检测到模拟器疑似假后台，准备强制关闭..."
        osascript -e 'quit app "Simulator"' >/dev/null 2>&1 || true
        xcrun simctl shutdown all >/dev/null 2>&1 || true
        pkill -f Simulator >/dev/null 2>&1 || true
        success_echo "✅ 假后台模拟器已关闭"
    else
        success_echo "✅ 模拟器状态正常"
    fi
}

# ✅ 启动模拟器并等待启动完成 🚀
boot_simulator() {
    info_echo "🚀 正在启动模拟器：$SIMULATOR_NAME"
    open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID"

    info_echo "⏳ 等待模拟器完全启动..."
    while true; do
        local booted
        booted=$(xcrun simctl list devices booted | grep "$SIMULATOR_UDID")
        [[ -n "$booted" ]] && break
        sleep 1
    done

    success_echo "✅ 模拟器已成功启动"
}

# ✅ 录制后生成 GIF（可选） 🌀
convert_recording_to_gif() {
    local input_file="$RECORD_FILE"

    if [[ -z "$input_file" || ! -f "$input_file" ]]; then
        warn_echo "⚠️ 未找到可转换的视频文件，跳过 GIF 生成"
        return 0
    fi

    read "?✨ 是否将该视频转换为 GIF？(Y/n)： " answer
    answer=${answer:-Y}
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        info_echo "⏭️ 用户选择不生成 GIF"
        return 0
    fi

    # 检查 ffmpeg 和 gifski
    if ! command -v ffmpeg &>/dev/null; then
        warn_echo "🧩 未检测到 ffmpeg，使用 Homebrew 安装..."
        brew install ffmpeg || { error_echo "❌ ffmpeg 安装失败"; return 1; }
    fi

    if ! command -v gifski &>/dev/null; then
        warn_echo "🧩 未检测到 gifski，使用 Homebrew 安装..."
        brew install gifski || { error_echo "❌ gifski 安装失败"; return 1; }
    fi

    # 询问 GIF 参数
    read "?📏 GIF 宽度（默认 540）： " gif_width
    gif_width=${gif_width:-540}

    read "?🎞 GIF 帧率 fps（默认 20）： " gif_fps
    gif_fps=${gif_fps:-20}

    # 规范化输入路径
    local input_abs
    input_abs="$(cd "$(dirname "$input_file")" && pwd)/$(basename "$input_file")"
    local input_dir
    input_dir="$(dirname "$input_abs")"
    local input_base
    input_base="$(basename "$input_abs" .mp4)"
    local frame_dir="${input_dir}/${input_base}_frames_$(date +%s)"
    local output_gif="${input_dir}/${input_base}.gif"

    mkdir -p "$frame_dir" || { error_echo "❌ 创建帧目录失败：$frame_dir"; return 1; }

    info_echo "🔧 使用 ffmpeg 导出 PNG 帧..."
    (
        cd "$frame_dir" || exit 1
        ffmpeg -y -i "$input_abs" -vf "fps=${gif_fps},scale=${gif_width}:-1:flags=lanczos" frame_%04d.png
    ) || { error_echo "❌ ffmpeg 导出帧失败"; return 1; }

    info_echo "✨ 使用 gifski 合成高质量 GIF..."
    (
        cd "$frame_dir" || exit 1
        gifski -o "$output_gif" --fps "$gif_fps" frame_*.png
    ) || { error_echo "❌ gifski 生成 GIF 失败"; return 1; }

    success_echo "🎉 GIF 生成完成：$output_gif"

    # 询问是否清理帧目录
    read "?🧹 是否删除临时帧文件夹？(Y/n)： " clean_answer
    clean_answer=${clean_answer:-Y}
    if [[ "$clean_answer" =~ ^[Yy]$ ]]; then
        rm -rf "$frame_dir"
        info_echo "🧼 已删除临时帧目录：$frame_dir"
    else
        note_echo "📂 已保留帧目录：$frame_dir"
    fi

    open "$output_gif"
}

# ✅ 开始录制视频 🎥
start_recording() {
    read "?📝 请输入视频文件名（无需加 .mp4，默认 output）： " filename
    filename=${filename:-output}
    RECORD_FILE="${filename}.mp4"

    info_echo "🎥 开始录制中...（再次回车停止）"
    xcrun simctl io "$SIMULATOR_UDID" recordVideo "$RECORD_FILE" &
    RECORD_PID=$!

    read "?⏹️ 录制中，按回车停止..."
    kill -INT "$RECORD_PID" 2>/dev/null || true
    wait "$RECORD_PID" 2>/dev/null || true

    success_echo "🎉 录制完成：$RECORD_FILE"
    open "$RECORD_FILE"

    # ✅ 这里才会问你要不要转 GIF —— 录屏已经结束
    convert_recording_to_gif
}

# ✅ 主函数入口 🧠
main() {
    print_intro                         # ✅ 自述信息
    install_homebrew                    # ✅ 自检安装 Homebrew
    install_fzf                         # ✅ 自检安装 fzf
    success_echo "✅ 必要工具已准备就绪"
    select_simulator_device             # ✅ 选择模拟器设备（fzf）
    shutdown_fake_background_simulator  # ✅ 关闭假后台模拟器
    boot_simulator                      # ✅ 启动模拟器并等待完成
    start_recording                     # ✅ 开始录制视频 → 录完再问是否转 GIF
}

main "$@"
