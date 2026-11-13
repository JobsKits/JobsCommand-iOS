#!/bin/zsh
# 脚本自述：
# - 核心用途：隔离验证 CodeGraph 安装器的依赖修复、失败阻断与真实建图状态校验。
# - 影响范围：只在 /private/tmp 创建测试文件，不调用真实 brew/npm 安装，不写用户配置。
# - 运行方式：/bin/zsh Tests/installer-health.zsh；真实样例需额外指定 --real-engine。
# shell: zsh

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

TEST_DIR=""
INSTALLER=""
TEST_ROOT=""
REAL_NODE=""
FAILED=0
PASSED=0
# 在任何临时写入前说明测试范围并校验运行参数。
show_test_intro() {
  print -r -- 'CodeGraph 安装器隔离验证：所有包管理器写操作均被 mock；仅 --real-engine 使用现有 CLI 建图。'
  [[ $# == 0 || ( $# == 1 && "$1" == --real-engine ) ]] || { print -u2 -r -- '仅支持可选参数 --real-engine。'; exit 2; }
}
# 初始化临时根目录与真实 JSON 解析器，绝不重设 HOME。
initialize_tests() {
  setopt NO_NOMATCH PIPE_FAIL
  TEST_DIR="${${(%):-%x}:A:h}"
  INSTALLER="${TEST_DIR:h}/${${TEST_DIR:h}:t}"
  REAL_NODE="$(command -v node)" || exit 1
  TEST_ROOT="$(mktemp -d /private/tmp/jobs-codegraph-tests.XXXXXX)" || exit 1
  trap 'cleanup_tests; exit 130' INT TERM
  /usr/bin/awk '$0 != "main \"$@\"" { print }' "$INSTALLER" > "$TEST_ROOT/definitions.zsh" || exit 1
}
# 只删除本次测试拥有的明确临时目录。
cleanup_tests() {
  [[ "$TEST_ROOT" == /private/tmp/jobs-codegraph-tests.* && -d "$TEST_ROOT" ]] || return 0
  /bin/rm -r -- "$TEST_ROOT"
}
# 构造通过状态文件控制的假命令，保留真实业务函数执行。
write_fixture_commands() {
  /bin/mkdir -p "$TEST_ROOT/fixtures"
  cat > "$TEST_ROOT/fixtures/brew" <<'BREW'
#!/bin/zsh
print -r -- "brew:$*" >> "$MOCK_TRACE"
[[ "$(<"$MOCK_STATE/brew")" == 1 ]] || exit 127
case "$1" in
  --version) print -r -- 'Homebrew mock' ;;
  --prefix) [[ "$2" == node@24 ]] && print -r -- "$MOCK_NODE_PREFIX" || print -r -- "$MOCK_BREW_PREFIX" ;;
  shellenv) print -r -- ':' ;;
  config) exit 0 ;;
  doctor) [[ "$(<"$MOCK_STATE/doctor")" == 1 ]] ;;
  list) [[ "$(<"$MOCK_STATE/node")" == 1 ]] ;;
  install|reinstall|upgrade)
    [[ "$(<"$MOCK_STATE/node_install_ok")" == 1 ]] || exit 42
    print -r -- 1 > "$MOCK_STATE/node"
    [[ "$(<"$MOCK_STATE/node_repair_ok")" == 1 ]] || exit 0
    print -r -- 1 > "$MOCK_STATE/node_health"
    print -r -- 1 > "$MOCK_STATE/npm_health"
    print -r -- 24 > "$MOCK_STATE/node_major"
    ;;
  update) exit 0 ;;
  *) exit 61 ;;
esac
BREW
  cat > "$TEST_ROOT/fixtures/node" <<'NODE'
#!/bin/zsh
print -r -- "node:$1" >> "$MOCK_TRACE"
[[ "$(<"$MOCK_STATE/node")" == 1 && "$(<"$MOCK_STATE/node_health")" == 1 ]] || exit 43
if [[ "$1" == --version ]]; then
  print -r -- "v$(<"$MOCK_STATE/node_major").0.0"
elif [[ "$1" == -e && "$2" == *'process.versions.node'* ]]; then
  MOCK_NODE_MAJOR="$(<"$MOCK_STATE/node_major")" "$MOCK_REAL_NODE" -e 'Object.defineProperty(process.versions,"node",{value:process.env.MOCK_NODE_MAJOR+".0.0"}); eval(process.argv[1]);' "$2"
else
  exec "$MOCK_REAL_NODE" "$@"
fi
NODE
  cat > "$TEST_ROOT/fixtures/npm" <<'NPM'
#!/bin/zsh
print -r -- "npm:$*" >> "$MOCK_TRACE"
[[ "$(<"$MOCK_STATE/node")" == 1 && "$(<"$MOCK_STATE/npm_health")" == 1 ]] || exit 44
case "$1" in
  --version) print -r -- 11.0.0 ;;
  config|root) print -r -- "$MOCK_CG_PREFIX" ;;
  ping) [[ "$(<"$MOCK_STATE/registry")" == 1 ]] ;;
  install)
    [[ "$(<"$MOCK_STATE/cg_install_ok")" == 1 ]] || exit 45
    print -r -- 1 > "$MOCK_STATE/codegraph"
    ;;
  *) exit 62 ;;
esac
NPM
  cat > "$TEST_ROOT/fixtures/codegraph" <<'CODEGRAPH'
#!/bin/zsh
print -r -- "codegraph:$*" >> "$MOCK_TRACE"
[[ "$(<"$MOCK_STATE/codegraph")" == 1 && "$(<"$MOCK_STATE/cg_health")" == 1 ]] || exit 46
if [[ "$1" == --version ]]; then
  print -r -- 1.6.2
elif [[ "$2" == --help ]]; then
  print -r -- "Usage: codegraph $1"
elif [[ "$1" == init ]]; then
  [[ "$CODEGRAPH_TELEMETRY" == 0 && "$CODEGRAPH_NO_DOWNLOAD" == 1 && "$NODE_DISABLE_COMPILE_CACHE" == 1 && "$CODEGRAPH_DIR" == .codegraph ]] || exit 63
  [[ "$(<"$MOCK_STATE/sample_init_ok")" == 1 ]] || exit 47
  /bin/mkdir -p "$3/.codegraph"
elif [[ "$1" == status ]]; then
  [[ "$CODEGRAPH_TELEMETRY" == 0 && "$CODEGRAPH_NO_DOWNLOAD" == 1 && "$NODE_DISABLE_COMPILE_CACHE" == 1 ]] || exit 64
  [[ "$(<"$MOCK_STATE/sample_status")" != malformed ]] || { print -r -- broken; exit 0; }
  "$MOCK_REAL_NODE" -e '
    const kind=process.argv[1], project=process.argv[2];
    console.log(JSON.stringify({initialized:kind!=="uninitialized",projectPath:kind==="wrongpath"?"/private/tmp":project,lastIndexed:kind==="no-time"?null:new Date().toISOString(),fileCount:kind==="empty"?0:1,nodeCount:kind==="empty"?0:2,index:{state:kind==="partial"?"partial":"complete"}}));' "$(<"$MOCK_STATE/sample_status")" "$3"
else
  exit 65
fi
CODEGRAPH
  /bin/chmod +x "$TEST_ROOT/fixtures/brew" "$TEST_ROOT/fixtures/node" "$TEST_ROOT/fixtures/npm" "$TEST_ROOT/fixtures/codegraph"
}
# 为每个场景建立独立命令、官方包身份和缺陷状态。
prepare_case() {
  local case_name="$1" key
  export MOCK_CASE="$TEST_ROOT/$case_name"
  export MOCK_STATE="$MOCK_CASE/state" MOCK_TRACE="$MOCK_CASE/trace"
  export MOCK_BREW_PREFIX="$MOCK_CASE/brew" MOCK_NODE_PREFIX="$MOCK_CASE/node"
  export MOCK_CG_PREFIX="$MOCK_CASE/codegraph" MOCK_REAL_NODE="$REAL_NODE"
  /bin/mkdir -p "$MOCK_STATE" "$MOCK_BREW_PREFIX/bin" "$MOCK_NODE_PREFIX/bin" "$MOCK_CG_PREFIX/bin" "$MOCK_CG_PREFIX/lib/node_modules/@colbymchenry/codegraph"
  : > "$MOCK_TRACE"
  for key in brew doctor node node_health npm_health node_install_ok node_repair_ok registry codegraph cg_install_ok cg_health sample_init_ok; do
    print -r -- 1 > "$MOCK_STATE/$key"
  done
  print -r -- complete > "$MOCK_STATE/sample_status"
  print -r -- 24 > "$MOCK_STATE/node_major"
  /bin/ln -s "$TEST_ROOT/fixtures/brew" "$MOCK_BREW_PREFIX/bin/brew"
  /bin/ln -s "$TEST_ROOT/fixtures/node" "$MOCK_NODE_PREFIX/bin/node"
  /bin/ln -s "$TEST_ROOT/fixtures/npm" "$MOCK_NODE_PREFIX/bin/npm"
  /bin/cp "$TEST_ROOT/fixtures/codegraph" "$MOCK_CG_PREFIX/lib/node_modules/@colbymchenry/codegraph/npm-shim.js"
  /bin/ln -s ../lib/node_modules/@colbymchenry/codegraph/npm-shim.js "$MOCK_CG_PREFIX/bin/codegraph"
  print -r -- '{"name":"@colbymchenry/codegraph","version":"1.6.2"}' > "$MOCK_CG_PREFIX/lib/node_modules/@colbymchenry/codegraph/package.json"
  case "$case_name" in
    endpoint_missing) print 0 > "$MOCK_STATE/codegraph" ;;
    consecutive_missing) print 0 > "$MOCK_STATE/brew"; print 0 > "$MOCK_STATE/node"; print 0 > "$MOCK_STATE/codegraph" ;;
    brew_install_failure) print 0 > "$MOCK_STATE/brew" ;;
    node_broken) print 0 > "$MOCK_STATE/node_health" ;;
    node_too_old) print 18 > "$MOCK_STATE/node_major" ;;
    healthy_node26) print 26 > "$MOCK_STATE/node_major" ;;
    npm_broken) print 0 > "$MOCK_STATE/npm_health" ;;
    node_recheck_failure) print 0 > "$MOCK_STATE/node_health"; print 0 > "$MOCK_STATE/node_repair_ok" ;;
    doctor_failure) print 0 > "$MOCK_STATE/doctor" ;;
    registry_failure) print 0 > "$MOCK_STATE/registry" ;;
    install_failure) print 0 > "$MOCK_STATE/codegraph"; print 0 > "$MOCK_STATE/cg_install_ok" ;;
    install_recheck_failure) print 0 > "$MOCK_STATE/codegraph"; print 0 > "$MOCK_STATE/cg_health" ;;
    sample_init_failure) print 0 > "$MOCK_STATE/sample_init_ok" ;;
    sample_*) print -r -- "${case_name#sample_}" > "$MOCK_STATE/sample_status" ;;
  esac
}
# 只替换输入、系统安装与配置落盘边界；依赖检查和失败传播保留原实现。
execute_mock_case() {
  source "$TEST_ROOT/definitions.zsh" || exit 1
  # 测试不需要用户输入，自述只记入轨迹。
  show_script_intro_and_wait() { print -r -- intro >> "$MOCK_TRACE"; }
  # 将运行态全部限制在本场景目录。
  initialize_runtime() {
    setopt NO_NOMATCH PIPE_FAIL
    LOG_FILE="$MOCK_CASE/installer.log"
    CODEGRAPH_PREFIX="$MOCK_CG_PREFIX"
    export PATH="$MOCK_NODE_PREFIX/bin:$PATH"
    : > "$LOG_FILE"
  }
  # 平台与CLT测试不触发系统安装器。
  check_system_toolchain() { print -r -- system-health >> "$MOCK_TRACE"; }
  # 自动允许必需修复，拒绝所有可选升级。
  ask_to_run() { [[ "$1" == *必需* || "$1" == *重新安装* ]]; }
  # 隔离发现范围，不能退回真实 /opt/homebrew。
  jobs_brew_find() {
    jobs_brew_candidate_ok "$MOCK_BREW_PREFIX/bin/brew" || return 1
    print -r -- "$MOCK_BREW_PREFIX/bin/brew"
  }
  # 缺失安装只设置用户模式，无真实交互。
  jobs_brew_choose_installation() { JOBS_HOMEBREW_INSTALL_MODE=user; }
  # 模拟官方安装成功或失败，不下载或更改真实Homebrew。
  jobs_brew_install_user() {
    print -r -- brew-bootstrap >> "$MOCK_TRACE"
    [[ "$MOCK_CASE" != */brew_install_failure ]] || return 48
    print 1 > "$MOCK_STATE/brew"
    JOBS_HOMEBREW_BIN="$MOCK_BREW_PREFIX/bin/brew"
    jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN"
  }
  # Homebrew配置落盘由轨迹替代。
  jobs_brew_save_shellenv() { print -r -- save-brew-env >> "$MOCK_TRACE"; }
  # CodeGraph发现仅允许本场景的候选，身份和可执行验证保留。
  find_codegraph() {
    codegraph_candidate_ok "$MOCK_CG_PREFIX/bin/codegraph" || return 1
    CODEGRAPH_BIN="$MOCK_CG_PREFIX/bin/codegraph"
  }
  # 不修改真实zprofile，只记录完成边界。
  save_codegraph_environment() { print -r -- save-codegraph-env >> "$MOCK_TRACE"; }
  main
}
# 断言场景轨迹中包含关键动作。
assert_contains() {
  /usr/bin/grep -Fq -- "$1" "$MOCK_TRACE" || { print -u2 -r -- "缺少轨迹：$1"; return 1; }
}
# 断言故障之后没有触发下游动作。
assert_absent() {
  ! /usr/bin/grep -Fq -- "$1" "$MOCK_TRACE" || { print -u2 -r -- "不应出现轨迹：$1"; return 1; }
}
# 确认修复仅执行一次，没有隐式重试。
assert_once() {
  [[ "$(/usr/bin/grep -Fc -- "$1" "$MOCK_TRACE")" == 1 ]] || { print -u2 -r -- "动作次数不为1：$1"; return 1; }
}
# 检查分支行为，而不是只看最终退出码。
assert_case_behavior() {
  local case_name="$1" result="$2"
  case "$case_name" in
    healthy|healthy_node26|endpoint_missing|consecutive_missing|node_broken|npm_broken|node_too_old)
      (( result == 0 )) || return 1
      assert_contains 'brew:doctor' && assert_contains 'npm:ping ' && assert_contains 'save-codegraph-env' || return 1
      ;;
    *) (( result != 0 )) && assert_absent 'save-codegraph-env' || return 1 ;;
  esac
  case "$case_name" in
    healthy|healthy_node26) assert_absent 'brew:install ' && assert_absent 'brew:reinstall ' && assert_absent 'npm:install ' ;;
    endpoint_missing) assert_once 'npm:install ' && assert_absent 'brew:install ' ;;
    consecutive_missing) assert_once brew-bootstrap && assert_once 'brew:install node@24' && assert_once 'npm:install ' ;;
    node_broken|npm_broken|node_too_old) assert_once 'brew:reinstall node@24' && assert_absent 'npm:install ' ;;
    brew_install_failure) assert_once brew-bootstrap && assert_absent 'brew:doctor' && assert_absent 'npm:ping ' ;;
    doctor_failure) assert_absent 'node:--version' && assert_absent 'npm:ping ' ;;
    registry_failure) assert_contains 'npm:ping ' && assert_absent 'npm:install ' && assert_absent 'codegraph:init --yes' ;;
    node_recheck_failure) assert_once 'brew:reinstall node@24' && assert_absent 'npm:ping ' ;;
    install_failure|install_recheck_failure) assert_once 'npm:install ' && assert_absent 'codegraph:init --yes' ;;
    sample_*) assert_once 'codegraph:init --yes' ;;
  esac
}
# 遍历核心依赖缺失、损坏和虚假成功场景。
run_mock_tests() {
  local case_name result
  for case_name in healthy healthy_node26 endpoint_missing consecutive_missing node_broken npm_broken node_too_old brew_install_failure doctor_failure registry_failure node_recheck_failure install_failure install_recheck_failure sample_init_failure sample_partial sample_uninitialized sample_wrongpath sample_no-time sample_empty sample_malformed; do
    prepare_case "$case_name" || return 1
    (execute_mock_case) > "$MOCK_CASE/output.log" 2>&1
    result=$?
    if assert_case_behavior "$case_name" "$result"; then
      (( PASSED += 1 ))
      print -r -- "PASS $case_name"
    else
      (( FAILED += 1 ))
      print -u2 -r -- "FAIL $case_name (exit=$result)"
      /bin/cat "$MOCK_CASE/output.log" >&2
    fi
  done
}
# 可选使用现有CLI执行一次真实样例，禁用下载、遥测、编译缓存和后台watcher。
perform_real_engine_test() {
  local installed_cli="$(command -v codegraph)" real_sample="$TEST_ROOT/real-engine" report
  [[ -x "$installed_cli" ]] || { print -u2 -r -- '缺少现有CodeGraph，未执行真实样例。'; return 1; }
  /bin/mkdir -p "$real_sample"
  print -r -- 'export function healthy(value) { return value + 1; }' > "$real_sample/health.js"
  env CODEGRAPH_NO_WATCH=1 CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$installed_cli" init --yes "$real_sample" > "$TEST_ROOT/real-engine.log" 2>&1 || return 1
  report="$(env CODEGRAPH_NO_WATCH=1 CODEGRAPH_DIR=.codegraph CODEGRAPH_TELEMETRY=0 CODEGRAPH_NO_DOWNLOAD=1 NODE_DISABLE_COMPILE_CACHE=1 "$installed_cli" status --json "$real_sample")" || return 1
  print -r -- "$report" | "$REAL_NODE" -e '
    const fs=require("node:fs"), s=JSON.parse(fs.readFileSync(0,"utf8"));
    if(s.initialized!==true||fs.realpathSync(s.projectPath)!==fs.realpathSync(process.argv[1])||!s.lastIndexed||s.index?.state!=="complete"||s.fileCount<1||s.nodeCount<1)process.exit(1);
    console.log(`PASS real-engine (${s.fileCount} file, ${s.nodeCount} nodes, ${s.index.state})`);' "$real_sample" || return 1
}
# 让可选真实验证的失败进入最终汇总，不能被后续输出覆盖。
run_real_engine_test() {
  [[ "${1:-}" == --real-engine ]] || return 0
  if ! perform_real_engine_test; then
    (( FAILED += 1 ))
    print -u2 -r -- 'FAIL real-engine'
    [[ ! -f "$TEST_ROOT/real-engine.log" ]] || /bin/cat "$TEST_ROOT/real-engine.log" >&2
  fi
}
# 汇报断言结果并传递失败状态。
finish_tests() {
  cleanup_tests || (( FAILED += 1 ))
  print -r -- "Mock scenarios: $PASSED passed, $FAILED failed"
  (( FAILED == 0 ))
}
# 编排隔离夹具、故障覆盖与可选真实内核验证。
main() {
  show_test_intro "$@" # 解释验证边界并确认参数。
  initialize_tests # 建立临时目录并提取安装器定义。
  write_fixture_commands # 创建不会触发真实安装的假命令。
  run_mock_tests # 验证依赖修复、阻断与假成功识别。
  run_real_engine_test "$@" # 可选验证本机已装CodeGraph真实建图。
  finish_tests # 输出汇总并返回断言状态。
}

main "$@"
