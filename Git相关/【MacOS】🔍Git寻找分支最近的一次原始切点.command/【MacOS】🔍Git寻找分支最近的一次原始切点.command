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
  # ================================== git-branch-origin-from-branch ==================================
  # 交互选择一个分支，推断它“最初从哪条分支切出来”
  # - 先 reflog（本机创建过就能直接看到来源）
  # - 再拓扑：在所有分支里排名最近父分支，输出分叉点和“切出后首个独有提交”
  # ================================================================================================

  export GIT_PAGER=cat
  export PAGER=cat

  set -e
  set -u
  set -o pipefail

  # 统一的 git 调用：固定仓库目录 + 禁用分页器
  G() { git -C "$SCRIPT_DIR" --no-pager "$@"; }

  # --- PATH（双击 .command 时常常很干净） ---
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # --- 初始脚本目录（bash/zsh 通吃） ---
  SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd -P)"

  # ---------- 简单输出（到 TTY，避免污染 stdout） ----------
  say()      { print -r -- "$*" > /dev/tty; }
  ok()       { say "✅ $*"; }
  info()     { say "ℹ️  $*"; }
  warn()     { say "⚠️  $*"; }
  err()      { say "❌ $*"; }

  # ---------- 去 ANSI & 路径清理 ----------
  _strip_ansi() { perl -pe 's/\e\[[0-9;]*[A-Za-z]//g'; }
  sanitize_path() {
    local p; p="$(print -r -- "${1:-}" | _strip_ansi)"
    p="${p//$'\r'/}"                                            # 去 CR（拖拽常见）
    p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"  # 去首尾空白
    p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"               # 去引号
    [[ "$p" == "~"* ]] && p="${p/#\~/$HOME}"                        # 展开 ~
    [[ "$p" != "/" ]] && p="${p%/}"
    print -r -- "$p"
  }
  abs_path() {
    local p; p="$(sanitize_path "$1")"; [[ -z "$p" ]] && return 1
    if [[ -d "$p" ]]; then ( builtin cd -P -- "$p" 2>/dev/null && pwd -P ) || return 1
    elif [[ -f "$p" ]]; then ( builtin cd -P -- "${p:h}" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "${p:t}" ) || return 1
    else return 1
    fi
  }

  # ---------- Git 仓库判定（只认工作副本：.git 目录/文件） ----------
  is_git_repo() {
    local dir="$1"
    [[ -d "$dir/.git" || -f "$dir/.git" ]] && return 0
    return 1
  }

  # ---------- 询问直到拿到 Git 仓库，并 cd 进去 ----------
  ask_git_repo() {
    local default_dir="$1" candidate ap
    while :; do
      say "📂 请拖入/输入 Git 仓库目录（直接回车 = 使用脚本所在目录）："
      print -n -- "> " > /dev/tty
      IFS= read -r candidate < /dev/tty || candidate=""
      candidate="$(sanitize_path "$candidate")"

      if [[ -z "$candidate" ]]; then
        ap="$(abs_path "$default_dir" || true)"
      else
        ap="$(abs_path "$candidate" || true)"
      fi

      if [[ -n "${ap:-}" && -d "$ap" ]]; then
        if is_git_repo "$ap"; then
          typeset -g SCRIPT_DIR="$ap"
          builtin cd -P -- "$SCRIPT_DIR" || { err "无法进入目录：$SCRIPT_DIR"; exit 1; }
          ok "确认 Git 仓库：$SCRIPT_DIR"
          say "📍 当前目录：$PWD"
          return 0
        else
          err "不是 Git 仓库：$ap"
        fi
      else
        err "无效路径：${candidate:-<空>}"
      fi
    done
  }

  # ---------- 分支选择（支持 fzf，也可手输） ----------
  list_all_branches() {
    git -C "$SCRIPT_DIR" for-each-ref --format='%(refname:short)' refs/heads refs/remotes \
    | grep -v '^origin/HEAD$' | sort -u
  }
  pick_target_branch() {
    local choice=""
    if command -v fzf >/dev/null 2>&1; then
      choice="$(list_all_branches | fzf --height=80% --reverse --prompt='选择要分析的分支： ')" || choice=""
    fi
    if [[ -z "$choice" ]]; then
      say "请输入要分析的分支名（例如：Hi 或 origin/Hi）："
      print -n -- "> " > /dev/tty
      IFS= read -r choice < /dev/tty || choice=""
    fi
    [[ -z "$choice" ]] && { err "未输入分支名"; exit 2; }
    print -r -- "$choice"
  }

  # ---------- reflog：本机创建过就能看到来源 ----------
  origin_from_reflog() {
    # 仅对“本地分支”有效；remote 分支没有 reflog
    local br="$1"
    br="${br#refs/heads/}"
    br="${br#origin/}"                 # 用户可能输入 origin/xxx；reflog 只看本地
    local line src
    line="$(git -C "$SCRIPT_DIR" log -g --date=iso --format='%gd|%gs' "refs/heads/$br" 2>/dev/null | tail -n1 || true)"
    [[ -z "$line" ]] && return 1
    # 典型格式：
    #   branch: Created from <src>
    #   checkout: moving from <src> to <br>
    src="$(sed -nE 's/.*branch: Created from ([^ ]+).*/\1/p' <<<"${line#*|}")"
    [[ -z "$src" ]] && src="$(sed -nE 's/.*checkout: moving from ([^ ]+) to .*/\1/p' <<<"${line#*|}")"
    [[ -n "$src" ]] || return 1
    print -r -- "$src|$line"
  }

  # ---------- 拓扑：fork-point / merge-base ----------
  _fork_point() {
    local base="$1" head="$2" fk=""
    fk="$(git -C "$SCRIPT_DIR" merge-base --fork-point "$base" "$head" 2>/dev/null || true)"
    [[ -z "$fk" ]] && fk="$(git -C "$SCRIPT_DIR" merge-base "$base" "$head" 2>/dev/null || true)"
    print -r -- "$fk"
  }
  first_unique_after_fork() {
    local fork="$1" head="$2"
    git -C "$SCRIPT_DIR" rev-list --ancestry-path "$fork..$head" --reverse | head -n1 || true
  }

  # ---------- 在所有分支里对“父分支”打分并取 Top1 ----------
  # 在所有分支里对“父分支”打分并取 Top1（输出一行，使用真实的 TAB 分隔）
  # 在所有分支里对“父分支”打分并取 Top1（输出一行，字段用真实 TAB 分隔）
  rank_parent_for_target() {
    local target="$1"
    list_all_branches | while IFS= read -r br; do
      [[ -z "$br" || "$br" == "$target" ]] && continue

      local fk ct ha ba lr behind ahead score
      fk="$(_fork_point "$br" "$target")"       || continue
      [[ -z "$fk" ]] && continue

      ct="$(G show -s --format=%ct "$fk" 2>/dev/null || echo 0)"
      ha="$(G rev-list --first-parent "$fk..$target" --count 2>/dev/null || echo 0)"
      ba="$(G rev-list --first-parent "$fk..$br"     --count 2>/dev/null || echo 0)"
      lr="$(G rev-list --left-right --count "$br...$target" 2>/dev/null || echo "0 0")"
      behind="${lr%% *}"; ahead="${lr##* }"

      # 评分：越新越好（ct），父分支在 fork 后越“干净”越好（ba）
      score=$(( ct * 1000 - ba * 50 ))

      # 关键：printf 打印真实 TAB
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$score" "$ct" "$br" "$fk" "$ha" "$ba" "$ahead" "$behind"
    done | sort -nr -k1,1 | head -n1
  }

  session_once() {
    # ① 选目标分支
    local TARGET; TARGET="$(pick_target_branch)"
    info "目标分支：$TARGET"

    # ② reflog 直接线索（若该分支在本机创建过）
    local refl src when msg
    if refl="$(origin_from_reflog "$TARGET")"; then
      src="${refl%%|*}"; msg="${refl#*|}"; when="${msg%%|*}"
      ok   "reflog：$TARGET 最初来自 '$src'"
      say  "🕒 创建记录：${when#*@\{}"
      say  "📝 线索：${msg#*|}"
    else
      warn "本机 reflog 无法确定 $TARGET 的来源（可能不是在本机创建的）。"
    fi

    # ③ 拓扑：最近父分支 + 分叉点
    local row; row="$(rank_parent_for_target "$TARGET")" || { err "无法通过拓扑推断父分支。"; return 1; }
    local SCORE CT PARENT FORK HA BA AHEAD BEHIND
    IFS=$'\t' read -r SCORE CT PARENT FORK HA BA AHEAD BEHIND <<< "$row"

    ok "推测父分支：$PARENT"
    say "── 分叉点（fork-point / merge-base）：$FORK"
    G show -s --format=$'哈希: %H\n作者: %an <%ae>\n时间: %ad\n标题: %s' --date=iso "$FORK" > /dev/tty

    # ④ 切出后首个独有提交
    local FU; FU="$(G rev-list --ancestry-path "$FORK..$TARGET" --reverse | head -n1 || true)"
    if [[ -n "$FU" ]]; then
      say
      info "切出后首个独有提交："
      G show -s --format=$'哈希: %H\n作者: %an <%ae>\n时间: %ad\n标题: %s' --date=iso "$FU" > /dev/tty
    fi

    # ⑤ 统计（重新算一次，避免字段黏连）
    local lr; lr="$(G rev-list --left-right --count "$PARENT...$TARGET" 2>/dev/null || echo "0 0")"
    local BEH="${lr%% *}" AH="${lr##* }"
    say
    say "📊 统计：相对父分支 ahead=$AH, behind=$BEH；从分叉点到目标分支（first-parent）提交数=$HA"
    [[ -n "${src:-}" ]] && say "📎 备注：reflog 显示初始来源为 '$src'（若与拓扑不一致，请以实际工作流为准）。"
  }


  # ---------- 主流程 ----------
  main() {
    say "┌──────────────────────────────────────────────────────────────┐"
    say "│  选择一个分支，推断它最初从哪条分支切出来                     │"
    say "└──────────────────────────────────────────────────────────────┘"
    say "按回车继续（Ctrl+C 退出）..."
    read -r _ < /dev/tty || true

    info "脚本所在目录：$SCRIPT_DIR"
    # 第一次先选仓库（函数里会设置 SCRIPT_DIR 并 cd 进去）
    ask_git_repo "$SCRIPT_DIR"

    while :; do
      session_once     # 跑一轮

      say
      say "继续吗？（回车=继续分析其它分支｜c=更换仓库｜q=退出）"
      print -n -- "> " > /dev/tty
      local ans; IFS= read -r ans < /dev/tty || ans="q"
      case "$ans" in
        q|Q) break ;;
        c|C) ask_git_repo "$SCRIPT_DIR" ;;   # 允许更换仓库后继续
        *)   ;;                              # 默认继续，用当前仓库再选分支
      esac
    done
  }

  # ---------- 入口 ----------
  if [[ "${(%):-%x}" == "$0" ]]; then
    main "$@"
  fi

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
