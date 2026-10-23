#!/bin/zsh
# shell: zsh
# 仅调用 Homebrew 官方卸载器；共享目录不做额外递归删除。
# --dry-run 只显示本地目标，不下载、不卸载。实际卸载须在终端输入 YES。

SCRIPT_SOURCE="${(%):-%x}"
WORK_DIR=""
LOG_FILE=""

TRAPEXIT() {
  local result=$?
  [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]] || /bin/rm -rf -- "$WORK_DIR"
  return "$result"
}
TRAPINT() { exit 130; }
TRAPTERM() { exit 143; }

fail() { print -u2 -r -- "错误：$*"; return 1; }

# 从安装本身取得 prefix，拒绝路径漂移和系统 / 用户根目录。
resolve_prefix() {
  local candidate="$1" actual=""
  [[ "$candidate" == /* && "$candidate" != *[[:cntrl:]]* ]] || { fail 'prefix 必须是无控制字符的绝对路径。'; return 1; }
  candidate="${candidate:A}"
  case "$candidate" in
    /|/usr|/opt|/Applications|/Library|/System|/Users|/tmp|/var|"${HOME:A}")
      fail "拒绝把系统或用户根目录作为 Homebrew prefix：$candidate"; return 1 ;;
  esac
  [[ -x "$candidate/bin/brew" ]] || { fail "未找到可执行的 $candidate/bin/brew"; return 1; }
  actual="$("$candidate/bin/brew" --prefix)" || { fail '无法读取 Homebrew prefix。'; return 1; }
  [[ "$actual" == /* && "$actual" != *[[:cntrl:]]* && "${actual:A}" == "$candidate" ]] || { fail 'Homebrew 返回的 prefix 与所选目录不一致。'; return 1; }
  REPLY="$candidate"
}

main() {
  setopt ERR_EXIT PIPE_FAIL
  local dry_run="${DRY_RUN:-0}" requested="" brew_bin="" prefix="" answer="" result=0
  local installer_url='https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh'
  while (( $# )); do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --prefix)
        (( $# >= 2 )) || { fail '--prefix 缺少目录。'; return 2; }
        requested="$2"; shift ;;
      --help|-h)
        print -r -- '用法：脚本 [--dry-run] [--prefix /绝对安装路径]；默认选择当前 brew，一次处理一套安装。'
        return 0 ;;
      *) fail "未知参数：$1"; return 2 ;;
    esac
    shift
  done
  [[ "$dry_run" == 0 || "$dry_run" == 1 ]] || { fail 'DRY_RUN 只能为 0 或 1。'; return 2; }
  [[ "$(uname -s)" == Darwin ]] || { fail '仅支持 macOS。'; return 1; }
  if [[ -z "$requested" ]]; then
    brew_bin="$(command -v brew 2>/dev/null || true)"
    if [[ -z "$brew_bin" ]]; then
      for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew "$HOME/.local/homebrew/bin/brew"; do
        [[ ! -x "$brew_bin" ]] || break
      done
    fi
    [[ -x "$brew_bin" ]] || { fail '未找到 Homebrew；可用 --prefix 指定安装目录。'; return 1; }
    requested="$("$brew_bin" --prefix)" || return 1
  fi
  resolve_prefix "$requested" || return 1
  prefix="$REPLY"
  print -r -- "Homebrew 卸载目标：$prefix"
  print -r -- "官方卸载器：$installer_url"
  print -r -- '将卸载此安装的包及 Homebrew 管理的文件；不会额外清空 /usr/local/bin、lib、etc 等共享目录。'
  if [[ "$dry_run" == 1 ]]; then
    print -r -- '预览结束，未下载、未删除任何内容。'
    return 0
  fi
  [[ -t 0 && -t 1 ]] || { fail '实际卸载必须在交互终端确认；自动检查请使用 --dry-run。'; return 1; }
  IFS= read -r 'answer?精确输入 YES 卸载以上安装；其它输入取消：' || return 130
  if [[ "$answer" != YES ]]; then print -r -- '已取消。'; return 0; fi
  # 确认后复核安装位置，再完整下载并校验语法，下载失败绝不进入执行。
  resolve_prefix "$prefix" || return 1
  command -v curl >/dev/null || { fail '缺少 curl。'; return 1; }
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-brew-uninstall.XXXXXXXX")" || return 1
  LOG_FILE="$(mktemp "${TMPDIR:-/tmp}/jobs-brew-uninstall-log.XXXXXXXX")" || return 1
  print -r -- "日志：$LOG_FILE"
  curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 120 --output "$WORK_DIR/uninstall.sh" "$installer_url" || return 1
  [[ -s "$WORK_DIR/uninstall.sh" ]] || { fail '下载结果为空。'; return 1; }
  /bin/bash -n "$WORK_DIR/uninstall.sh" || { fail '官方卸载器语法检查失败。'; return 1; }
  # 用户已对具体 prefix 输入 YES；退出码包含下载器 / 卸载器 / 日志失败。
  /bin/bash "$WORK_DIR/uninstall.sh" --path "$prefix" --force 2>&1 | tee -a "$LOG_FILE" || result=$?
  if (( result )); then
    print -u2 -r -- "错误：卸载未完成（退出码 $result），请检查日志：$LOG_FILE"
    return "$result"
  fi
  print -r -- "官方卸载流程完成。请按日志检查残留；日志：$LOG_FILE"
}

main "$@"
