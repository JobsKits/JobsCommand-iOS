#!/usr/bin/env bash

# ================================== 日志与输出函数 ==================================
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

# ================================== 写入 Homebrew shellenv ==================================
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

# ================================== 判断芯片架构（ARM64 / x86_64） ==================================
get_cpu_arch() {
    [[ $(uname -m) == "arm64" ]] && echo "arm64" || echo "x86_64"
}

# ================================== 自检安装 Homebrew（原逻辑） ==================================
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

# ================================== 自检安装 fzf（原逻辑） ==================================
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

# ================================== 自述说明 ==================================
print_readme() {
    bold_echo "🚀 Quicktype 自动安装 / 升级脚本"
    echo
    note_echo "本脚本将执行以下操作："
    gray_echo "  1) 检查并安装 / 更新 Homebrew"
    gray_echo "  2) 使用 Homebrew 检查并安装 / 升级 Node.js + npm"
    gray_echo "  3) 使用 Homebrew 检查并安装 / 升级 fzf"
    gray_echo "  4) 使用 npm 全局安装 / 升级 quicktype"
    gray_echo "  5) 完成后打印 quicktype 版本号"
    echo
    warm_echo "⚠ 过程中可能会请求 sudo 密码（用于 npm 全局安装 / 升级 quicktype）"
    echo
    read -r -p "👉 按回车继续执行，或 Ctrl + C 取消..." _
}

# ================================== Homebrew 安装 & 升级封装 ==================================
ensure_homebrew_and_upgrade() {
    install_homebrew

    if ! command -v brew &>/dev/null; then
        error_echo "❌ 未检测到 Homebrew，后续步骤无法继续"
        exit 1
    fi

    info_echo "🔄 正在更新 Homebrew 仓库..."
    brew update || warn_echo "⚠ Homebrew 更新失败，可稍后手动执行：brew update"

    info_echo "⬆ 正在升级已安装的 Homebrew 包（可能耗时较长）..."
    brew upgrade || warn_echo "⚠ Homebrew 升级过程中有错误，可稍后手动执行：brew upgrade"
}

# ================================== Node.js & npm 管理 ==================================
ensure_node_and_npm() {
    if brew list --versions node &>/dev/null; then
        info_echo "✅ 检测到通过 Homebrew 安装的 Node.js，尝试升级..."
        brew upgrade node || warn_echo "⚠ Node.js 升级失败，可稍后手动执行：brew upgrade node"
    else
        warn_echo "🧩 未检测到 Homebrew 管理的 Node.js，正在通过 Homebrew 安装 node（包含 npm）..."
        brew install node || {
            error_echo "❌ Node.js 安装失败，请检查 Homebrew 或网络"
            exit 1
        }
        success_echo "✅ Node.js 安装完成"
    fi

    info_echo "🔹 当前 Node.js 版本：$(node -v 2>/dev/null || echo '未检测到')"
    info_echo "🔹 当前 npm 版本：$(npm -v 2>/dev/null || echo '未检测到')"
}

# ================================== fzf 安装 & 升级封装 ==================================
ensure_fzf_with_upgrade() {
    if brew list --versions fzf &>/dev/null; then
        info_echo "✅ 检测到通过 Homebrew 安装的 fzf，尝试升级..."
        brew upgrade fzf || warn_echo "⚠ fzf 升级失败，可稍后手动执行：brew upgrade fzf"
    else
        install_fzf
    fi
}

# ================================== quicktype 安装 & 升级 ==================================
ensure_quicktype() {
    if ! command -v npm &>/dev/null; then
        error_echo "❌ 未检测到 npm，无法安装 quicktype，请先确保 Node.js 环境正常"
        exit 1
    fi

    if npm list -g quicktype --depth=0 >/dev/null 2>&1; then
        info_echo "✅ 检测到全局 quicktype，正在通过 npm 升级..."
        sudo npm update -g quicktype || {
            error_echo "❌ quicktype 升级失败，你可以稍后手动执行：sudo npm update -g quicktype"
            return 1
        }
        success_echo "✅ quicktype 已升级到最新版本"
    else
        warn_echo "🧩 未检测到全局 quicktype，正在通过 npm 安装..."
        sudo npm install -g quicktype || {
            error_echo "❌ quicktype 安装失败，你可以稍后手动执行：sudo npm install -g quicktype"
            return 1
        }
        success_echo "✅ quicktype 安装完成"
    fi
}

# ================================== 打印 quicktype 版本 ==================================
show_quicktype_version() {
    if command -v quicktype &>/dev/null; then
        local ver
        ver="$(quicktype --version 2>&1)"
        highlight_echo "🔹 当前 quicktype 版本：${ver}"
    else
        error_echo "❌ 未能检测到 quicktype 命令，请检查 npm 全局路径或重新安装"
    fi
}

# ================================== main 入口 ==================================
main() {
    print_readme
    ensure_homebrew_and_upgrade
    ensure_node_and_npm
    ensure_fzf_with_upgrade
    ensure_quicktype
    show_quicktype_version
    success_echo "🎉 Quicktype 自动安装 / 升级流程已结束"
}

main "$@"

