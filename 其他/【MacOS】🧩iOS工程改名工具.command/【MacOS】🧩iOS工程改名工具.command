#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩iOS工程改名工具.command
# - 核心用途：交互选择 iOS 工程，支持原地改名或复制开版后改名，并可选执行 Pods 维护。
# - 影响范围：会修改目标工程内文本、文件名、目录名；复制开版模式会创建新工程副本。
# - 运行提示：运行后会先打印内置自述并等待确认；删除、安装依赖等高风险动作会单独确认。

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
    jobs_style_original_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        jobs_style_reply=''
        jobs_style_query_buffer=''
        jobs_style_query_target_reply=''
        jobs_style_query_target_normalized=''
        jobs_style_query_target_rgb=''
        jobs_style_query_st="${jobs_style_esc}\\"
        jobs_style_query_stale_count=0
        jobs_style_query_phase=${2:-strict}
        jobs_style_query_cr=$(printf '\r')
        jobs_style_query_lf=$(printf '\n.')
        jobs_style_query_lf=${jobs_style_query_lf%.}
        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'
        for jobs_style_query_round in 1 2 3; do
            printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || {
                jobs_style_query_failure='无法向原终端发送配色查询'
                return 1
            }
            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。
                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')
                jobs_style_piece=${jobs_style_piece%.}
                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece
                while [ -n "$jobs_style_query_buffer" ]; do
                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ] || [ "$jobs_style_query_phase" = applied ]; then
                        jobs_style_query_control_sequence=''
                        jobs_style_query_control_partial=0
                        case $jobs_style_query_buffer in
                            "$jobs_style_query_cr"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;
                            "$jobs_style_query_lf"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;
                        esac
                        if [ -z "$jobs_style_query_control_sequence" ]; then
                            for jobs_style_query_direction in A B C D; do
                                for jobs_style_query_control_candidate in \
                                    "${jobs_style_esc}[${jobs_style_query_direction}" \
                                    "${jobs_style_esc}O${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;2${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;3${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;4${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;5${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;6${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;7${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;8${jobs_style_query_direction}"; do
                                    case $jobs_style_query_buffer in
                                        "$jobs_style_query_control_candidate"*)
                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate
                                            break 2
                                            ;;
                                    esac
                                    case $jobs_style_query_control_candidate in
                                        "$jobs_style_query_buffer"*) jobs_style_query_control_partial=1 ;;
                                    esac
                                done
                            done
                        fi
                        if [ -n "$jobs_style_query_control_sequence" ]; then
                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))
                            if [ "$jobs_style_phase_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'
                                return 1
                            fi
                            jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_control_sequence"}
                            continue
                        fi
                        if [ "$jobs_style_query_control_partial" = 1 ]; then
                            break
                        fi
                    fi
                    case $jobs_style_query_buffer in
                        "$jobs_style_esc"|"$jobs_style_esc]") break ;;
                        "$jobs_style_esc]"*) ;;
                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;
                    esac
                    jobs_style_query_head=''
                    jobs_style_query_terminator=''
                    case $jobs_style_query_buffer in
                        *"$jobs_style_bel"*)
                            jobs_style_query_head=${jobs_style_query_buffer%%"$jobs_style_bel"*}
                            jobs_style_query_terminator=$jobs_style_bel
                            ;;
                    esac
                    case $jobs_style_query_buffer in
                        *"$jobs_style_query_st"*)
                            jobs_style_query_st_head=${jobs_style_query_buffer%%"$jobs_style_query_st"*}
                            if [ -z "$jobs_style_query_terminator" ] ||
                               [ "${#jobs_style_query_st_head}" -lt "${#jobs_style_query_head}" ]; then
                                jobs_style_query_head=$jobs_style_query_st_head
                                jobs_style_query_terminator=$jobs_style_query_st
                            fi
                            ;;
                    esac
                    [ -n "$jobs_style_query_terminator" ] || break
                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator
                    jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_frame"}
                    jobs_style_query_body=${jobs_style_query_head#"$jobs_style_esc]"}
                    case $jobs_style_query_body in
                        *';rgb:'*) ;;
                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;
                    esac
                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}
                    case $jobs_style_query_frame_key in
                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;
                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;
                    esac
                    jobs_style_query_frame_rgb=${jobs_style_query_body#"$jobs_style_query_frame_key;rgb:"}
                    jobs_style_query_frame_normalized=$(printf '%s\n' "$jobs_style_query_frame_rgb" | LC_ALL=C awk -F/ '
                        BEGIN { valid = 1 }
                        NR != 1 || NF != 3 { valid = 0; exit }
                        {
                            for (i = 1; i <= 3; i++) {
                                h = tolower($i)
                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {
                                    valid = 0
                                    exit
                                }
                                n = 0
                                for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                            }
                        }
                        END {
                            if (!valid || NR != 1) exit 1
                            printf "%d/%d/%d", value[1], value[2], value[3]
                        }
                    ')
                    if [ -z "$jobs_style_query_frame_normalized" ]; then
                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'
                        return 1
                    fi
                    if [ "$jobs_style_query_frame_key" = "$jobs_style_query_key" ]; then
                        if [ -n "$jobs_style_query_target_reply" ] &&
                           [ "$jobs_style_query_target_normalized" != "$jobs_style_query_frame_normalized" ]; then
                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'
                            return 1
                        fi
                        jobs_style_query_target_reply=$jobs_style_query_frame
                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized
                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb
                    else
                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))
                        if [ "$jobs_style_query_stale_count" -gt 128 ]; then
                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'
                            return 1
                        fi
                    fi
                done
                if [ -n "$jobs_style_query_target_reply" ] && [ -z "$jobs_style_query_buffer" ]; then
                    jobs_style_reply=$jobs_style_query_target_reply
                    jobs_style_normalized=$jobs_style_query_target_normalized
                    jobs_style_rgb=$jobs_style_query_target_rgb
                    return 0
                fi
            done
            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。
            if [ -n "$jobs_style_query_buffer" ]; then
                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'
                return 1
            fi
        done
        return 1
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
    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。
    jobs_terminal_style_rollback() {
        jobs_style_rollback_issue='无法读取或设置原终端输入模式'
        jobs_style_rollback_safe=''
        jobs_style_rollback_conflicts=''
        jobs_style_phase_control_keys=0
        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
        if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
            jobs_style_query_active=1
            jobs_style_rollback_ok=1
            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do
                [ -n "$jobs_style_key" ] || continue
                if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                    jobs_style_rollback_ok=0
                    jobs_style_rollback_issue="回退颜色项 $jobs_style_key：$jobs_style_query_failure"
                    break
                fi
                if [ "$jobs_style_normalized" = "$jobs_style_original_normalized" ]; then
                    continue
                elif jobs_terminal_style_accepts_target "$jobs_style_key"; then
                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original
                else
                    jobs_style_rollback_conflicts="$jobs_style_rollback_conflicts $jobs_style_key"
                fi
            done <<JOBS_STYLE_ROLLBACK
$jobs_style_original_rows
JOBS_STYLE_ROLLBACK
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }
            jobs_style_query_active=0
            if [ "$jobs_style_rollback_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_rollback_safe" > /dev/tty; then
                if [ -z "$jobs_style_rollback_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                    return 0
                fi
                printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_rollback_conflicts" >&2
                jobs_style_rollback_issue="核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts"
            fi
        fi
        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_rollback_issue" "$jobs_style_recovery" >&2
        return 1
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ] && [ "$jobs_style_applied_complete" != 1 ]; then
            if jobs_terminal_style_rollback; then
                jobs_style_changed=0
            else
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
            if [ "${2:-}" = continue ]; then
                jobs_style_cleanup_status=$jobs_style_result
                return 0
            fi
            exit "$jobs_style_result"
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_phase_control_keys=0
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                            jobs_style_cleanup_ok=0
                            jobs_style_cleanup_issue="颜色项 $jobs_style_key：$jobs_style_query_failure"
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }
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
                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_cleanup_issue" "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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
        jobs_style_original_rows="$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply
"
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
    jobs_style_phase_control_keys=0
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key" applied; then
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
        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\n' "$jobs_style_key" "$jobs_style_query_failure" >&2
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_applied_complete=1
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

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
LOG_FILE="${TMPDIR:-/tmp/}${SCRIPT_BASENAME}.log"

SOURCE_PROJECT_ROOT=""
PROJECT_ROOT=""
ORIGINAL_PROJECT_ROOT=""
OLD_PROJECT_NAME=""
NEW_PROJECT_NAME=""
WORK_MODE="inplace"
COPY_PARENT_DIR=""
COPIED_PROJECT_ROOT=""
BACKUP_ZIP_PATH=""
WORKSPACE_ALIAS_PATH=""
TEXT_CHANGED_COUNT=0
FILE_RENAMED_COUNT=0
DIR_RENAMED_COUNT=0
CLEANED_ITEM_COUNT=0
POD_INSTALL_RAN="否"
FAILED_COUNT=0
FAILURE_MESSAGES=()
RENAME_PATHS=()

# 判断当前终端是否适合彩色输出。
supports_color() {
  [[ -t 1 && -z "${NO_COLOR:-}" && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}
# 写入一行终端输出，并同步追加到日志文件。
log() {
  local message="$1"
  print -r -- "$message" | jobs_prompt_tee "$LOG_FILE"
}
# 使用指定颜色输出日志，不支持彩色时自动降级为纯文本。
color_log() {
  local color="$1"
  local message="$2"
  local reset=$'\033[0m'
  if supports_color; then
    log "${color}${message}${reset}"
  else
    log "$message"
  fi
}
# 输出普通绿色日志。
color_echo() {
  color_log $'\033[1;32m' "$1"
}
# 输出信息日志。
info_echo() {
  color_log $'\033[1;34m' "ℹ $1"
}
# 输出成功日志。
success_echo() {
  color_log $'\033[1;32m' "✔ $1"
}
# 输出警告日志。
warn_echo() {
  color_log $'\033[1;33m' "⚠ $1"
}
# 输出温馨提示日志。
warm_echo() {
  color_log $'\033[1;33m' "$1"
}
# 输出说明日志。
note_echo() {
  color_log $'\033[1;35m' "➤ $1"
}
# 输出错误日志。
error_echo() {
  color_log $'\033[1;31m' "✖ $1"
}
# 输出错误纯文本日志。
err_echo() {
  color_log $'\033[1;31m' "$1"
}
# 输出调试日志。
debug_echo() {
  color_log $'\033[1;35m' "🐞 $1"
}
# 输出高亮日志。
highlight_echo() {
  color_log $'\033[1;36m' "🔹 $1"
}
# 输出次要信息日志。
gray_echo() {
  color_log $'\033[0;90m' "$1"
}
# 输出加粗日志。
bold_echo() {
  color_log $'\033[1m' "$1"
}
# 输出下划线日志。
underline_echo() {
  color_log $'\033[4m' "$1"
}
# 初始化本次运行日志文件。
prepare_runtime_log() {
  : > "$LOG_FILE"
}
# 在完整终端中清屏，避免瘦身终端出现 TERM 报错。
clear_screen_if_possible() {
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi
}
# 打印脚本内置自述，并等待用户确认后继续。
show_script_intro_and_wait() {
  prepare_runtime_log
  clear_screen_if_possible
  highlight_echo "══════════════════════════════ 脚本自述 ══════════════════════════════" | jobs_intro_style title
  note_echo "当前脚本：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：iOS 工程改名；支持原地改名，也支持复制新副本后开版改名。" | jobs_intro_style body
  warn_echo "影响范围：会修改目标工程内文本、文件名、目录名，必要时重命名工程根目录。" | jobs_intro_style body
  warn_echo "开版模块：复制副本、清 Pods / lock / workspace、pod install、workspace 快捷方式均为可选。" | jobs_intro_style body
  warn_echo "跳过目录：.git、Pods、node_modules、.dart_tool、build、DerivedData。" | jobs_intro_style body
  gray_echo "备份策略：直接回车跳过；输入任意字符后回车会先打包 zip。" | jobs_intro_style body | jobs_prompt_filter
  gray_echo "危险策略：删除类维护动作必须输入 YES 才会执行。" | jobs_intro_style body
  gray_echo "日志位置：${LOG_FILE}" | jobs_intro_style body
  gray_echo "取消方式：确认前或真实改名前按 Ctrl+C 终止。" | jobs_intro_style body
  highlight_echo "═════════════════════════════════════════════════════════════════════" | jobs_intro_style title
  echo "" | jobs_intro_style body
  if [[ ! -t 0 ]]; then
    error_echo "当前没有可交互输入，请在终端中双击或手动运行本脚本。"
    exit 1
  fi
  read -r "_?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")"
}
# 初始化 zsh 运行选项。
configure_shell_runtime() {
  setopt NO_NOMATCH
}
# 检查脚本依赖的 macOS 基础命令是否存在。
check_environment() {
  local missing_count=0
  local command_name=""
  local -a required_commands=(basename date dirname ditto find grep head ln mkdir mv osascript perl rm rsync sed sort tee)
  for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      error_echo "缺少必要命令：${command_name}"
      missing_count=$((missing_count + 1))
    fi
  done
  if [[ "$missing_count" -gt 0 ]]; then
    error_echo "环境检查未通过，请补齐上面的系统命令后重试。"
    exit 1
  fi
  success_echo "环境检查通过"
}
# 去掉字符串首尾空白。
trim_text() {
  print -r -- "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}
# 展开用户输入路径中的家目录符号。
expand_home_path() {
  local value="$1"
  if [[ "$value" == "~" ]]; then
    print -r -- "$HOME"
  elif [[ "$value" == "~/"* ]]; then
    print -r -- "${HOME}/${value#~/}"
  else
    print -r -- "$value"
  fi
}
# 从用户拖入或输入的内容中解析第一个路径。
normalize_dragged_input() {
  local raw_value="$1"
  local trimmed_value=""
  local first_path=""
  local -a path_parts=()
  raw_value="${raw_value%$'\r'}"
  raw_value="${raw_value%$'\n'}"
  trimmed_value="$(trim_text "$raw_value")"
  if [[ -z "$trimmed_value" ]]; then
    print -r -- ""
    return 0
  fi
  path_parts=("${(z)trimmed_value}")
  if [[ "${#path_parts[@]}" -gt 1 ]]; then
    warn_echo "检测到多个路径，本次只使用第一个路径：${(Q)path_parts[1]}"
  fi
  first_path="${(Q)path_parts[1]}"
  expand_home_path "$first_path"
}
# 将已存在路径规范化为真实绝对路径。
canonicalize_existing_path() {
  local input_path="$1"
  local dir_name=""
  local base_name=""
  if [[ -z "$input_path" ]]; then
    print -r -- ""
    return 0
  fi
  if [[ -d "$input_path" ]]; then
    (cd "$input_path" 2>/dev/null && pwd -P) || print -r -- "$input_path"
    return 0
  fi
  if [[ -e "$input_path" || -L "$input_path" ]]; then
    dir_name="$(dirname "$input_path")"
    base_name="$(basename "$input_path")"
    (cd "$dir_name" 2>/dev/null && print -r -- "$(pwd -P)/${base_name}") || print -r -- "$input_path"
    return 0
  fi
  print -r -- "$input_path"
}
# 解析 Unix 软链接路径。
resolve_unix_symlink_path() {
  local input_path="$1"
  local link_target=""
  local link_dir=""
  if [[ -z "$input_path" || ! -L "$input_path" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  link_target="$(readlink "$input_path" 2>/dev/null || true)"
  if [[ -z "$link_target" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  if [[ "$link_target" != /* ]]; then
    link_dir="$(dirname "$input_path")"
    link_target="${link_dir}/${link_target}"
  fi
  canonicalize_existing_path "$link_target"
}
# 解析 Finder 替身路径，解析失败时保持原路径。
resolve_finder_alias_path() {
  local input_path="$1"
  local resolved_path=""
  if [[ -z "$input_path" || ! -e "$input_path" ]]; then
    print -r -- "$input_path"
    return 0
  fi
  resolved_path="$(osascript - "$input_path" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set inputPath to item 1 of argv
    try
        tell application "Finder"
            set inputItem to (POSIX file inputPath) as alias
            try
                set originalItemPath to POSIX path of ((original item of inputItem) as alias)
                return originalItemPath
            on error
                return inputPath
            end try
        end tell
    on error
        return inputPath
    end try
end run
APPLESCRIPT
)"
  if [[ -n "$resolved_path" ]]; then
    print -r -- "$resolved_path"
  else
    print -r -- "$input_path"
  fi
}
# 连续解析软链接和 Finder 替身，最多解析十层。
resolve_real_path() {
  local input_path="$1"
  local current_path=""
  local next_path=""
  local index=0
  current_path="$(canonicalize_existing_path "$input_path")"
  while [[ "$index" -lt 10 ]]; do
    next_path="$(resolve_unix_symlink_path "$current_path")"
    next_path="$(resolve_finder_alias_path "$next_path")"
    next_path="$(canonicalize_existing_path "$next_path")"
    if [[ "$next_path" == "$current_path" ]]; then
      break
    fi
    current_path="$next_path"
    index=$((index + 1))
  done
  print -r -- "$current_path"
}
# 如果用户拖入工程文件或配置文件，则回退到其父目录作为工程根目录。
coerce_project_root() {
  local input_path="$1"
  local base_name=""
  if [[ -z "$input_path" ]]; then
    print -r -- ""
    return 0
  fi
  base_name="$(basename "$input_path")"
  if [[ -d "$input_path" && ( "$base_name" == *.xcodeproj || "$base_name" == *.xcworkspace ) ]]; then
    canonicalize_existing_path "$(dirname "$input_path")"
    return 0
  fi
  if [[ -f "$input_path" ]]; then
    case "$base_name" in
      Package.swift|Podfile|Podfile.lock|*.podspec)
        canonicalize_existing_path "$(dirname "$input_path")"
        return 0
        ;;
    esac
  fi
  print -r -- "$input_path"
}
# 判断目录是否具备 iOS / Xcode / Pod / SPM 工程特征。
is_valid_ios_project_root() {
  local project_root="$1"
  local marker_path=""
  if [[ -z "$project_root" || ! -d "$project_root" ]]; then
    return 1
  fi
  marker_path="$(find "$project_root" -maxdepth 2 \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Package.swift" -o -name "Podfile" -o -name "*.podspec" \) -print -quit 2>/dev/null)"
  [[ -n "$marker_path" ]]
}
# 打印当前识别到的工程特征文件，方便用户确认。
print_project_markers() {
  local project_root="$1"
  local marker_path=""
  local display_path=""
  local shown_count=0
  note_echo "已识别到的工程特征："
  while IFS= read -r marker_path; do
    shown_count=$((shown_count + 1))
    [[ "$shown_count" -gt 8 ]] && break
    display_path="${marker_path#${project_root}/}"
    [[ "$display_path" == "$marker_path" ]] && display_path="."
    gray_echo "  - ${display_path}"
  done < <(find "$project_root" -maxdepth 2 \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "Package.swift" -o -name "Podfile" -o -name "*.podspec" \) -print 2>/dev/null)
}
# 循环要求用户输入正确的 iOS 工程目录。
request_project_root_until_valid() {
  local raw_input=""
  local normalized_path=""
  local resolved_path=""
  local candidate_root=""
  while true; do
    echo ""
    note_echo "请把 iOS 工程目录拖到这里，或手动输入工程目录路径。"
    gray_echo "支持 .xcodeproj / .xcworkspace / Package.swift / Podfile / *.podspec 所在目录。"
    IFS= read -r "raw_input?➤ 工程路径："
    normalized_path="$(normalize_dragged_input "$raw_input")"
    resolved_path="$(resolve_real_path "$normalized_path")"
    candidate_root="$(coerce_project_root "$resolved_path")"
    candidate_root="$(canonicalize_existing_path "$candidate_root")"
    if is_valid_ios_project_root "$candidate_root"; then
      SOURCE_PROJECT_ROOT="$candidate_root"
      PROJECT_ROOT="$candidate_root"
      ORIGINAL_PROJECT_ROOT="$candidate_root"
      success_echo "工程目录确认：${PROJECT_ROOT}"
      print_project_markers "$PROJECT_ROOT"
      break
    fi
    warn_echo "输入未通过 iOS 工程检测，请重新输入正确工程目录。"
    gray_echo "统一判定：空白、路径不存在、不是目录、目录内没有工程特征，都会回到本步骤继续询问。"
  done
}
# 从工程标记文件中推断当前旧工程名。
detect_old_project_name() {
  local marker_path=""
  local package_name=""
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcodeproj" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .xcodeproj)"
    return 0
  fi
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .xcworkspace)"
    return 0
  fi
  marker_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.podspec" -print 2>/dev/null | sort | head -1)"
  if [[ -n "$marker_path" ]]; then
    OLD_PROJECT_NAME="$(basename "$marker_path" .podspec)"
    return 0
  fi
  if [[ -f "${PROJECT_ROOT}/Package.swift" ]]; then
    package_name="$(grep -E '^[[:space:]]*name:[[:space:]]*"[^"]+"' "${PROJECT_ROOT}/Package.swift" 2>/dev/null | head -1 | sed -E 's/.*name:[[:space:]]*"([^"]+)".*/\1/')"
    if [[ -n "$package_name" ]]; then
      OLD_PROJECT_NAME="$package_name"
      return 0
    fi
  fi
  OLD_PROJECT_NAME="$(basename "$PROJECT_ROOT")"
}
# 判断工程名是否适合作为文件名和替换关键字。
is_valid_project_name() {
  local project_name="$1"
  project_name="$(trim_text "$project_name")"
  [[ -n "$project_name" && "$project_name" != "." && "$project_name" != ".." && "$project_name" != *"/"* && "$project_name" != *":"* ]]
}
# 允许用户修正脚本自动推断的旧工程名。
request_old_project_name_override() {
  local answer=""
  while true; do
    echo ""
    note_echo "检测到当前旧工程名：${OLD_PROJECT_NAME}"
    IFS= read -r "answer?$(jobs_prompt_render "➤ 直接回车沿用；如果检测不准，请输入旧工程名：")"
    answer="$(trim_text "$answer")"
    if [[ -z "$answer" ]]; then
      if is_valid_project_name "$OLD_PROJECT_NAME"; then
        success_echo "旧工程名确认：${OLD_PROJECT_NAME}"
        return 0
      fi
      warn_echo "自动推断的旧工程名不可用，请手动输入。"
    elif is_valid_project_name "$answer"; then
      OLD_PROJECT_NAME="$answer"
      success_echo "旧工程名确认：${OLD_PROJECT_NAME}"
      return 0
    else
      warn_echo "工程名不能为空，也不能包含 / 或 :，请重新输入。"
    fi
  done
}
# 循环要求用户输入新的工程项目名。
request_new_project_name_until_valid() {
  local answer=""
  while true; do
    echo ""
    note_echo "请输入要改成的新工程项目名。"
    gray_echo "示例：JobsApp / JobsSwiftDemo / JobsOCBaseConfigDemo"
    IFS= read -r "answer?➤ 新工程名："
    answer="$(trim_text "$answer")"
    if ! is_valid_project_name "$answer"; then
      warn_echo "新工程名不能为空，也不能包含 / 或 :，请重新输入。"
      continue
    fi
    if [[ "$answer" == "$OLD_PROJECT_NAME" ]]; then
      warn_echo "新工程名和旧工程名相同，没有改名意义，请重新输入。"
      continue
    fi
    NEW_PROJECT_NAME="$answer"
    success_echo "新工程名确认：${NEW_PROJECT_NAME}"
    break
  done
}
# 询问用户选择原地改名还是复制开版。
request_work_mode() {
  local answer=""
  while true; do
    echo ""
    note_echo "请选择运行模式。"
    gray_echo "1：原地改名，直接修改你拖入的工程目录。"
    gray_echo "2：复制开版，先复制工程副本到指定目录，再对副本改名。"
    IFS= read -r "answer?$(jobs_prompt_render "➤ 运行模式（直接回车=1）：")" 
    answer="$(trim_text "$answer")"
    case "$answer" in
      ""|1)
        WORK_MODE="inplace"
        success_echo "运行模式：原地改名"
        return 0
        ;;
      2)
        WORK_MODE="copy"
        success_echo "运行模式：复制开版"
        return 0
        ;;
      *)
        jobs_prompt_output warn_echo "请输入 1 / 2，或直接回车使用原地改名。"
        ;;
    esac
  done
}
# 收集工程目录、旧工程名、新工程名和运行模式。
collect_user_inputs() {
  request_project_root_until_valid
  detect_old_project_name
  request_old_project_name_override
  request_new_project_name_until_valid
  request_work_mode
}
# 询问用户是否执行普通可选动作。
ask_any_to_run() {
  local message="$1"
  local answer=""
  IFS= read -r "answer?$(jobs_prompt_render "${message}（直接回车跳过；输入任意字符后回车执行）：")"
  [[ -n "$answer" ]]
}
# 危险动作必须输入 YES 才允许继续。
confirm_yes() {
  local message="$1"
  local answer=""
  echo ""
  warn_echo "$message"
  jobs_prompt_output gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  IFS= read -r "answer?➤ "
  [[ "$answer" == "YES" ]]
}
# 询问复制开版的父目录并确认目标目录不存在。
request_copy_parent_until_valid() {
  local raw_input=""
  local normalized_path=""
  local resolved_path=""
  local target_path=""
  while true; do
    echo ""
    note_echo "请输入复制开版的父目录。"
    jobs_prompt_output gray_echo "直接回车使用桌面：${HOME}/Desktop"
    IFS= read -r "raw_input?➤ 开版父目录："
    raw_input="$(trim_text "$raw_input")"
    if [[ -z "$raw_input" ]]; then
      resolved_path="${HOME}/Desktop"
    else
      normalized_path="$(normalize_dragged_input "$raw_input")"
      resolved_path="$(resolve_real_path "$normalized_path")"
    fi
    resolved_path="$(canonicalize_existing_path "$resolved_path")"
    if [[ ! -d "$resolved_path" ]]; then
      warn_echo "父目录不存在或不是目录，请重新输入。"
      continue
    fi
    target_path="${resolved_path}/${NEW_PROJECT_NAME}"
    if [[ -e "$target_path" || -L "$target_path" ]]; then
      warn_echo "开版目标已存在，避免覆盖：${target_path}"
      continue
    fi
    COPY_PARENT_DIR="$resolved_path"
    COPIED_PROJECT_ROOT="$target_path"
    success_echo "开版目标确认：${COPIED_PROJECT_ROOT}"
    return 0
  done
}
# 复制工程到新的开版目录，并默认排除 .git。
copy_project_for_opening() {
  note_echo "开始复制工程副本，默认排除 .git：${SOURCE_PROJECT_ROOT} -> ${COPIED_PROJECT_ROOT}"
  if mkdir -p "$COPIED_PROJECT_ROOT" && rsync -a --exclude ".git" "${SOURCE_PROJECT_ROOT}/" "${COPIED_PROJECT_ROOT}/"; then
    PROJECT_ROOT="$COPIED_PROJECT_ROOT"
    ORIGINAL_PROJECT_ROOT="$COPIED_PROJECT_ROOT"
    success_echo "工程副本已创建：${PROJECT_ROOT}"
  else
    error_echo "复制开版失败，已终止。"
    exit 1
  fi
}
# 根据运行模式准备真正要改名的工程目录。
prepare_project_workspace() {
  if [[ "$WORK_MODE" == "copy" ]]; then
    request_copy_parent_until_valid
    copy_project_for_opening
  else
    gray_echo "原地改名模式：将直接处理 ${PROJECT_ROOT}"
  fi
}
# 创建工程 zip 备份，失败时终止后续改名。
create_project_backup() {
  local parent_dir=""
  local timestamp=""
  local zip_name=""
  parent_dir="$(dirname "$PROJECT_ROOT")"
  timestamp="$(date '+%Y%m%d_%H%M%S')"
  zip_name="${OLD_PROJECT_NAME}_rename_backup_${timestamp}.zip"
  BACKUP_ZIP_PATH="${parent_dir}/${zip_name}"
  note_echo "开始创建备份：${BACKUP_ZIP_PATH}"
  if ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT" "$BACKUP_ZIP_PATH"; then
    success_echo "备份完成：${BACKUP_ZIP_PATH}"
  else
    error_echo "备份失败，已终止改名，避免无备份继续修改工程。"
    exit 1
  fi
}
# 根据用户输入决定是否先备份工程。
ask_backup_and_run_if_needed() {
  echo ""
  if ask_any_to_run "👉 是否先把当前待改工程打包成 zip 备份"; then
    create_project_backup
  else
    warn_echo "已跳过 zip 备份；后续会直接修改当前待改工程。"
  fi
}
# 记录单项失败信息并增加失败计数。
record_failure() {
  local message="$1"
  FAILED_COUNT=$((FAILED_COUNT + 1))
  FAILURE_MESSAGES+=("$message")
  error_echo "$message"
}
# 判断路径是否属于默认跳过目录。
is_ignored_path() {
  local path_value="$1"
  [[ "$path_value" == */.git || "$path_value" == */.git/* ]] && return 0
  [[ "$path_value" == */Pods || "$path_value" == */Pods/* ]] && return 0
  [[ "$path_value" == */node_modules || "$path_value" == */node_modules/* ]] && return 0
  [[ "$path_value" == */.dart_tool || "$path_value" == */.dart_tool/* ]] && return 0
  [[ "$path_value" == */build || "$path_value" == */build/* ]] && return 0
  [[ "$path_value" == */DerivedData || "$path_value" == */DerivedData/* ]] && return 0
  return 1
}
# 判断文件是否可以按文本方式安全替换。
is_text_file() {
  local file_path="$1"
  [[ -f "$file_path" && -s "$file_path" ]] || return 1
  LC_ALL=C grep -Iq . "$file_path" 2>/dev/null
}
# 替换工程内文本文件中的旧工程名。
replace_text_occurrences() {
  local file_path=""
  note_echo "开始替换文本内容..."
  while IFS= read -r -d '' file_path; do
    is_ignored_path "$file_path" && continue
    is_text_file "$file_path" || continue
    if LC_ALL=C grep -Fq -- "$OLD_PROJECT_NAME" "$file_path" 2>/dev/null; then
      if OLD_PROJECT_NAME="$OLD_PROJECT_NAME" NEW_PROJECT_NAME="$NEW_PROJECT_NAME" perl -0pi -e 's/\Q$ENV{OLD_PROJECT_NAME}\E/$ENV{NEW_PROJECT_NAME}/g' "$file_path"; then
        TEXT_CHANGED_COUNT=$((TEXT_CHANGED_COUNT + 1))
        gray_echo "已替换文本：${file_path}"
      else
        record_failure "文本替换失败：${file_path}"
      fi
    fi
  done < <(find "$PROJECT_ROOT" \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o -type f -print0 2>/dev/null)
}
# 收集需要改名的文件和目录路径。
collect_paths_for_rename() {
  local current_path=""
  local base_name=""
  RENAME_PATHS=()
  while IFS= read -r -d '' current_path; do
    [[ "$current_path" == "$PROJECT_ROOT" ]] && continue
    is_ignored_path "$current_path" && continue
    base_name="$(basename "$current_path")"
    if [[ "$base_name" == *"$OLD_PROJECT_NAME"* ]]; then
      RENAME_PATHS+=("$current_path")
    fi
  done < <(find "$PROJECT_ROOT" \( -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" \) -prune -o -print0 2>/dev/null)
  RENAME_PATHS=("${(O)RENAME_PATHS[@]}")
}
# 重命名单个文件或目录路径。
rename_one_path() {
  local current_path="$1"
  local parent_dir=""
  local base_name=""
  local new_base_name=""
  local target_path=""
  [[ -e "$current_path" || -L "$current_path" ]] || return 0
  parent_dir="$(dirname "$current_path")"
  base_name="$(basename "$current_path")"
  new_base_name="${base_name//$OLD_PROJECT_NAME/$NEW_PROJECT_NAME}"
  [[ "$new_base_name" == "$base_name" ]] && return 0
  target_path="${parent_dir}/${new_base_name}"
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    record_failure "改名目标已存在，已跳过：${target_path}"
    return 0
  fi
  if mv "$current_path" "$target_path"; then
    if [[ -d "$target_path" ]]; then
      DIR_RENAMED_COUNT=$((DIR_RENAMED_COUNT + 1))
      gray_echo "已重命名目录：${current_path} -> ${target_path}"
    else
      FILE_RENAMED_COUNT=$((FILE_RENAMED_COUNT + 1))
      gray_echo "已重命名文件：${current_path} -> ${target_path}"
    fi
  else
    record_failure "路径改名失败：${current_path}"
  fi
}
# 按从深到浅的顺序重命名工程内部文件和目录。
rename_nested_paths() {
  local current_path=""
  note_echo "开始重命名工程内部文件和目录..."
  collect_paths_for_rename
  if [[ "${#RENAME_PATHS[@]}" -eq 0 ]]; then
    gray_echo "未发现需要重命名的内部文件或目录。"
    return 0
  fi
  for current_path in "${RENAME_PATHS[@]}"; do
    rename_one_path "$current_path"
  done
}
# 如果工程根目录名称包含旧工程名，则最后再重命名根目录。
rename_project_root_if_needed() {
  local parent_dir=""
  local root_base_name=""
  local new_root_base_name=""
  local new_root_path=""
  root_base_name="$(basename "$PROJECT_ROOT")"
  if [[ "$root_base_name" != *"$OLD_PROJECT_NAME"* ]]; then
    gray_echo "工程根目录名称不包含旧工程名，跳过根目录改名。"
    return 0
  fi
  parent_dir="$(dirname "$PROJECT_ROOT")"
  new_root_base_name="${root_base_name//$OLD_PROJECT_NAME/$NEW_PROJECT_NAME}"
  new_root_path="${parent_dir}/${new_root_base_name}"
  if [[ -e "$new_root_path" || -L "$new_root_path" ]]; then
    record_failure "工程根目录改名目标已存在，已跳过：${new_root_path}"
    return 0
  fi
  if mv "$PROJECT_ROOT" "$new_root_path"; then
    DIR_RENAMED_COUNT=$((DIR_RENAMED_COUNT + 1))
    success_echo "工程根目录已改名：${PROJECT_ROOT} -> ${new_root_path}"
    PROJECT_ROOT="$new_root_path"
  else
    record_failure "工程根目录改名失败：${PROJECT_ROOT}"
  fi
}
# 执行 iOS 工程改名的核心业务。
rename_ios_project() {
  replace_text_occurrences
  rename_nested_paths
  rename_project_root_if_needed
}
# 删除单个路径并统计清理数量。
remove_path_if_exists() {
  local target_path="$1"
  if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
    gray_echo "未发现需要清理：${target_path}"
    return 0
  fi
  if rm -R "$target_path"; then
    CLEANED_ITEM_COUNT=$((CLEANED_ITEM_COUNT + 1))
    success_echo "已清理：${target_path}"
  else
    record_failure "清理失败：${target_path}"
  fi
}
# 清理 CocoaPods 生成目录、锁文件和 workspace。
clean_pods_generated_artifacts() {
  local workspace_path=""
  remove_path_if_exists "${PROJECT_ROOT}/Pods"
  remove_path_if_exists "${PROJECT_ROOT}/Podfile.lock"
  while IFS= read -r -d '' workspace_path; do
    remove_path_if_exists "$workspace_path"
  done < <(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" -print0 2>/dev/null)
}
# 执行 pod install 并记录结果。
run_pod_install_if_possible() {
  if [[ ! -f "${PROJECT_ROOT}/Podfile" ]]; then
    warn_echo "当前工程根目录没有 Podfile，跳过 pod install。"
    return 0
  fi
  if ! command -v pod >/dev/null 2>&1; then
    record_failure "未检测到 pod 命令，无法执行 pod install。"
    return 0
  fi
  note_echo "开始执行 pod install：${PROJECT_ROOT}"
  if (cd "$PROJECT_ROOT" && pod install); then
    POD_INSTALL_RAN="是"
    success_echo "pod install 执行完成"
  else
    POD_INSTALL_RAN="失败"
    record_failure "pod install 执行失败：${PROJECT_ROOT}"
  fi
}
# 查找当前工程根目录下优先使用的 workspace。
find_primary_workspace() {
  local workspace_path=""
  workspace_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "${NEW_PROJECT_NAME}.xcworkspace" -print 2>/dev/null | sort | head -1)"
  if [[ -z "$workspace_path" ]]; then
    workspace_path="$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" -print 2>/dev/null | sort | head -1)"
  fi
  print -r -- "$workspace_path"
}
# 在桌面创建 workspace 软链接快捷方式。
create_workspace_alias_on_desktop() {
  local workspace_path=""
  local alias_path=""
  workspace_path="$(find_primary_workspace)"
  if [[ -z "$workspace_path" || ! -e "$workspace_path" ]]; then
    warn_echo "未找到可创建快捷方式的 .xcworkspace。"
    return 0
  fi
  alias_path="${HOME}/Desktop/${NEW_PROJECT_NAME}.xcworkspace"
  if [[ -e "$alias_path" || -L "$alias_path" ]]; then
    record_failure "桌面快捷方式目标已存在，已跳过：${alias_path}"
    return 0
  fi
  if ln -s "$workspace_path" "$alias_path"; then
    WORKSPACE_ALIAS_PATH="$alias_path"
    success_echo "已创建 workspace 快捷方式：${alias_path}"
  else
    record_failure "创建 workspace 快捷方式失败：${alias_path}"
  fi
}
# 改名完成后询问是否执行开版维护模块。
ask_opening_modules_and_run_if_needed() {
  echo ""
  if ! ask_any_to_run "👉 是否进入开版维护模块"; then
    warn_echo "已跳过开版维护模块。"
    return 0
  fi
  if confirm_yes "是否删除 Pods、Podfile.lock 和当前根目录下的 *.xcworkspace？"; then
    clean_pods_generated_artifacts
  else
    warn_echo "已跳过删除 Pods / lock / workspace。"
  fi
  echo ""
  if ask_any_to_run "👉 是否执行 pod install"; then
    run_pod_install_if_possible
  else
    warn_echo "已跳过 pod install。"
  fi
  echo ""
  if ask_any_to_run "👉 是否在桌面创建 .xcworkspace 快捷方式"; then
    create_workspace_alias_on_desktop
  else
    warn_echo "已跳过 workspace 快捷方式。"
  fi
}
# 输出失败列表，便于根据日志继续排查。
print_failures_if_needed() {
  local message=""
  if [[ "$FAILED_COUNT" -le 0 ]]; then
    return 0
  fi
  warn_echo "失败明细如下："
  for message in "${FAILURE_MESSAGES[@]}"; do
    err_echo "  - ${message}"
  done
}
# 输出本次运行摘要并按失败状态返回。
show_summary() {
  echo ""
  highlight_echo "══════════════════════════════ 执行摘要 ══════════════════════════════"
  note_echo "运行模式：${WORK_MODE}"
  note_echo "源工程目录：${SOURCE_PROJECT_ROOT}"
  note_echo "旧工程名：${OLD_PROJECT_NAME}"
  note_echo "新工程名：${NEW_PROJECT_NAME}"
  note_echo "当前工程目录：${PROJECT_ROOT}"
  if [[ -n "$COPIED_PROJECT_ROOT" ]]; then
    gray_echo "开版副本目录：${COPIED_PROJECT_ROOT}"
  fi
  gray_echo "文本替换文件数：${TEXT_CHANGED_COUNT}"
  gray_echo "重命名文件数：${FILE_RENAMED_COUNT}"
  gray_echo "重命名目录数：${DIR_RENAMED_COUNT}"
  gray_echo "开版清理项数：${CLEANED_ITEM_COUNT}"
  gray_echo "pod install：${POD_INSTALL_RAN}"
  if [[ -n "$WORKSPACE_ALIAS_PATH" ]]; then
    gray_echo "workspace 快捷方式：${WORKSPACE_ALIAS_PATH}"
  fi
  if [[ -n "$BACKUP_ZIP_PATH" ]]; then
    gray_echo "备份文件：${BACKUP_ZIP_PATH}"
  else
    warn_echo "备份文件：未创建"
  fi
  gray_echo "日志文件：${LOG_FILE}"
  print_failures_if_needed
  highlight_echo "═════════════════════════════════════════════════════════════════════"
  if [[ "$FAILED_COUNT" -gt 0 ]]; then
    exit 1
  fi
  success_echo "iOS 工程改名 / 开版流程已完成"
}
# 编排脚本自述、环境检查和核心改名开版流程。
main() {
  show_script_intro_and_wait # 打印内置自述并等待确认，避免误触后直接修改工程。
  configure_shell_runtime # 初始化 zsh 运行选项，保证路径和通配符处理稳定。
  check_environment # 检查脚本依赖的 macOS 基础命令，缺失时提前终止。
  collect_user_inputs # 循环收集合法工程目录、旧工程名、新工程名和运行模式。
  prepare_project_workspace # 根据运行模式决定原地处理或先复制开版副本。
  ask_backup_and_run_if_needed # 询问是否创建 zip 备份，输入任意字符才执行备份。
  rename_ios_project # 执行文本替换、内部路径改名和工程根目录改名。
  ask_opening_modules_and_run_if_needed # 改名后按需执行清理 Pods、pod install 和 workspace 快捷方式。
  show_summary # 输出执行摘要、备份位置、日志位置和失败状态。
}

main "$@"
