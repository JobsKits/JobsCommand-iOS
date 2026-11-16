#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬simios.command
# - 核心用途：执行“⏬simios”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

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
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_MAGENTA='\033[35m'
C_RED='\033[31m'
C_GRAY='\033[90m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
LOG_DIR="${HOME}/Library/Logs/simios"
LOG_FILE="${LOG_DIR}/simios-$(date '+%Y%m%d-%H%M%S').log"

XCODE_APP=""
DEVELOPER_DIR_SELECTED=""
XCODEBUILD_BIN=""
VERBOSE_ARG=""
# 按当前输出级别记录终端信息，并同步写入脚本日志。
cecho() {
  local color="$1"
  shift
  printf "%b%s%b\n" "$color" "$*" "$C_RESET"
}
# 封装 line 对应的独立处理逻辑。
line() {
  cecho "$C_GRAY" "────────────────────────────────────────"
}
# 封装 section 对应的独立处理逻辑。
section() {
  echo ""
  cecho "$C_BOLD$C_CYAN" "▶ $1"
  line
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log() {
  cecho "$C_BLUE" "[simios] $1"
}
# 封装 ok 对应的独立处理逻辑。
ok() {
  cecho "$C_GREEN" "[OK] $1"
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn() {
  cecho "$C_YELLOW" "[WARN] $1"
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err() {
  cecho "$C_RED" "[ERR] $1"
}
# 封装 pause_enter 对应的独立处理逻辑。
pause_enter() {
  local message="${1:-按回车继续...}"
  printf "%b%s%b" "$C_MAGENTA" "$message" "$C_RESET"
  local _input=""
  IFS= read -r _input
}
# 收集并校验用户输入，决定后续执行路径。
ask_run() {
  local message="$1"
  local input=""
  jobs_prompt_output printf "%b%s%b" "$C_MAGENTA" "${message}（回车跳过，输入任意字符后回车执行）：" "$C_RESET"
  IFS= read -r input
  [[ -n "$input" ]]
}
# 执行已经拆分完成的独立业务步骤。
run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  clear || true
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】⏬simios.command' | jobs_intro_style title
  print -r -- '核心用途：执行“⏬simios”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  cecho "$C_BOLD$C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  cecho "$C_BOLD$C_CYAN" "        simios.command" | jobs_intro_style title
  cecho "$C_BOLD$C_CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | jobs_intro_style title
  cecho "$C_BLUE" "用途：检测 Xcode 环境，然后下载 / 补齐 iOS Simulator Runtime。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  cecho "$C_GREEN" "执行顺序：" | jobs_intro_style title
  cecho "$C_GRAY" "  1) 检测 macOS / Xcode.app 是否存在" | jobs_intro_style body
  cecho "$C_GRAY" "  2) 检测 xcodebuild 是否来自完整 Xcode，而不是只有 Command Line Tools" | jobs_intro_style body
  cecho "$C_GRAY" "  3) 检测 xcode-select 指向；不强制永久改系统，可临时使用 DEVELOPER_DIR" | jobs_intro_style body
  cecho "$C_GRAY" "  4) 检测 Xcode 首次启动组件 / license / 磁盘空间 / 网络连通" | jobs_intro_style body
  cecho "$C_GRAY" "  5) 最后由你决定是否执行 iOS 模拟器下载" | jobs_intro_style body
  echo "" | jobs_intro_style body
  cecho "$C_YELLOW" "交互规则：" | jobs_intro_style title
  jobs_prompt_output cecho "$C_GRAY" "  - 普通安装 / 更新动作：回车跳过，输入任意字符后回车执行" | jobs_intro_style body | jobs_prompt_filter
  cecho "$C_GRAY" "  - 必须修复项：脚本会明确说明原因，再让你继续" | jobs_intro_style body
  echo "" | jobs_intro_style body
  cecho "$C_GREEN" "核心下载命令：" | jobs_intro_style title
  cecho "$C_GRAY" "  xcodebuild -downloadPlatform iOS -verbose" | jobs_intro_style body
  echo "" | jobs_intro_style body
  cecho "$C_YELLOW" "说明：" | jobs_intro_style title
  cecho "$C_GRAY" "  xcodebuild 官方帮助里通常是单横线 -verbose；如果你的版本支持 --verbose，脚本会自动使用 --verbose。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  pause_enter "按回车开始体检..."
}
# 封装 require_macos 对应的独立处理逻辑。
require_macos() {
  section "系统检测"

  if [[ "$(uname -s)" != "Darwin" ]]; then
    err "当前不是 macOS，无法下载 Xcode iOS Simulator Runtime。"
    exit 1
  fi

  ok "当前系统是 macOS。"
}
# 封装 collect_xcode_apps 对应的独立处理逻辑。
collect_xcode_apps() {
  local -a found
  local item=""

  for item in \
    /Applications/Xcode.app \
    /Applications/Xcode*.app \
    "${HOME}/Applications/Xcode.app" \
    "${HOME}/Applications/Xcode"*.app \
    /Applications/Xcodes/Xcode*.app; do
    if [[ -d "${item}/Contents/Developer" && -x "${item}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      found+=("$item")
    fi
  done

  if (( ${#found[@]} > 0 )); then
    printf "%s\n" "${found[@]}" | awk '!seen[$0]++'
  fi
}
# 收集并校验用户输入，决定后续执行路径。
choose_xcode_app() {
  section "Xcode 检测"

  local active_dev=""
  local active_app=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  if [[ "$active_dev" == */Contents/Developer ]]; then
    active_app="${active_dev%/Contents/Developer}"
    if [[ -d "$active_app" && -x "${active_app}/Contents/Developer/usr/bin/xcodebuild" ]]; then
      XCODE_APP="$active_app"
      ok "当前 xcode-select 已指向完整 Xcode：$XCODE_APP"
      return 0
    fi
  fi

  local first_app=""
  first_app="$(collect_xcode_apps | head -n 1)"

  if [[ -z "$first_app" ]]; then
    err "未检测到完整 Xcode.app。"
    warn "只安装 Command Line Tools 没有现实意义：iOS Simulator Runtime 下载依赖完整 Xcode。"
    warn "请先安装 Xcode，再重新运行：$SCRIPT_PATH"
    echo ""
    cecho "$C_GRAY" "建议路径：/Applications/Xcode.app"
    cecho "$C_GRAY" "安装来源：Mac App Store 或 Apple Developer 下载页"
    exit 1
  fi

  XCODE_APP="$first_app"
  ok "检测到 Xcode：$XCODE_APP"
}
# 封装 maybe_check_xcode_update 对应的独立处理逻辑。
maybe_check_xcode_update() {
  echo ""
  if ask_run "Xcode 已存在，是否打开更新入口检查 Xcode 升级"; then
    if command -v mas >/dev/null 2>&1; then
      log "检测到 mas，尝试升级 App Store 版 Xcode。"
      mas upgrade 497799835 || open "macappstore://itunes.apple.com/app/id497799835" || true
    else
      warn "未检测到 mas。为了避免额外引入 Homebrew / mas，本脚本不自动安装它。"
      log "改为打开 App Store 的 Xcode 页面。"
      open "macappstore://itunes.apple.com/app/id497799835" || true
    fi
  else
    log "跳过 Xcode 升级检查。"
  fi
}
# 封装 prepare_developer_dir 对应的独立处理逻辑。
prepare_developer_dir() {
  section "xcode-select / DEVELOPER_DIR 检测"

  DEVELOPER_DIR_SELECTED="${XCODE_APP}/Contents/Developer"
  XCODEBUILD_BIN="${DEVELOPER_DIR_SELECTED}/usr/bin/xcodebuild"

  if [[ ! -x "$XCODEBUILD_BIN" ]]; then
    err "xcodebuild 不存在或不可执行：$XCODEBUILD_BIN"
    exit 1
  fi

  export DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED"

  local active_dev=""
  active_dev="$(xcode-select -p 2>/dev/null || true)"

  ok "本次脚本使用：DEVELOPER_DIR=$DEVELOPER_DIR_SELECTED"

  if [[ "$active_dev" == "$DEVELOPER_DIR_SELECTED" ]]; then
    ok "系统 xcode-select 指向正确。"
  else
    warn "系统 xcode-select 当前指向：${active_dev:-未设置}"
    warn "脚本本次会临时使用 DEVELOPER_DIR，不强制修改你的全局设置。"
    if ask_run "是否永久切换 xcode-select 到当前 Xcode"; then
      run_root xcode-select -s "$DEVELOPER_DIR_SELECTED"
      ok "已永久切换 xcode-select。"
    else
      log "跳过永久切换，仅本次脚本临时使用当前 Xcode。"
    fi
  fi
}
# 封装 show_xcode_version 对应的独立处理逻辑。
show_xcode_version() {
  section "Xcode 版本"
  "$XCODEBUILD_BIN" -version || {
    err "xcodebuild 无法正常输出版本。"
    exit 1
  }
}
# 检查当前运行条件是否满足后续流程要求。
check_xcodebuild_support() {
  section "xcodebuild 能力检测"

  local help_text=""
  help_text="$({ "$XCODEBUILD_BIN" -help || true; } 2>&1)"

  if ! printf "%s\n" "$help_text" | grep -q -- "downloadPlatform"; then
    err "当前 Xcode 的 xcodebuild 不支持 -downloadPlatform。"
    warn "这通常说明 Xcode 版本过旧，需要先升级 Xcode。"
    maybe_check_xcode_update
    exit 1
  fi

  ok "支持 -downloadPlatform。"

  if printf "%s\n" "$help_text" | grep -q -- "--verbose"; then
    VERBOSE_ARG="--verbose"
  else
    VERBOSE_ARG="-verbose"
  fi

  ok "verbose 参数使用：$VERBOSE_ARG"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_first_launch() {
  section "Xcode 首次启动组件检测"

  local help_text=""
  help_text="$({ "$XCODEBUILD_BIN" -help || true; } 2>&1)"

  if printf "%s\n" "$help_text" | grep -q -- "checkFirstLaunchStatus"; then
    if "$XCODEBUILD_BIN" -checkFirstLaunchStatus >/dev/null 2>&1; then
      ok "Xcode 首次启动组件状态正常。"
    else
      warn "Xcode 首次启动组件未完成。"
      warn "这属于执行 xcodebuild 下载前的必要支援项，需要安装 / 初始化。"
      pause_enter "按回车执行：sudo xcodebuild -runFirstLaunch ..."
      run_root "$XCODEBUILD_BIN" -runFirstLaunch
      ok "首次启动组件已处理。"
    fi
  else
    warn "当前 xcodebuild 不支持 -checkFirstLaunchStatus。"
    if ask_run "是否执行一次 xcodebuild -runFirstLaunch 做初始化"; then
      run_root "$XCODEBUILD_BIN" -runFirstLaunch
      ok "已执行首次启动初始化。"
    else
      log "跳过首次启动初始化。"
    fi
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_license() {
  section "Xcode License 检测"

  if "$XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    ok "Xcode license 已同意。"
    return 0
  fi

  warn "Xcode license 尚未同意。"
  warn "不同意 license 时，xcodebuild 后续下载大概率会失败。"
  pause_enter "按回车进入交互式 license 确认：sudo xcodebuild -license ..."
  run_root "$XCODEBUILD_BIN" -license

  if "$XCODEBUILD_BIN" -license check >/dev/null 2>&1; then
    ok "Xcode license 已同意。"
  else
    err "license 仍未通过检查，停止执行。"
    exit 1
  fi
}
# 检查当前运行条件是否满足后续流程要求。
check_disk_space() {
  section "磁盘空间检测"

  local free_kb="0"
  local free_gb="0"
  free_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
  free_gb=$(( free_kb / 1024 / 1024 ))

  if (( free_gb >= 30 )); then
    ok "当前用户目录所在磁盘可用空间约 ${free_gb}GB。"
  elif (( free_gb >= 15 )); then
    warn "当前可用空间约 ${free_gb}GB，可能够用，但大型 runtime 可能吃紧。"
  else
    warn "当前可用空间约 ${free_gb}GB，iOS Simulator Runtime 下载很可能失败。"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
check_network() {
  section "网络连通检测"

  if ! command -v curl >/dev/null 2>&1; then
    warn "未检测到 curl，跳过网络预检。macOS 正常情况下会自带 curl。"
    return 0
  fi

  if curl -Is --connect-timeout 10 https://developer.apple.com >/dev/null 2>&1; then
    ok "developer.apple.com 可连接。"
  else
    warn "developer.apple.com 连接预检失败。可能是网络、代理、VPN、DNS 或 Apple CDN 临时问题。"
    warn "这不是本地环境硬缺失，脚本不会自动改网络设置。"
  fi
}
# 封装 list_ios_runtimes 对应的独立处理逻辑。
list_ios_runtimes() {
  if DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl runtime list >/dev/null 2>&1; then
    DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl runtime list 2>/dev/null | grep -i "iOS" || true
  else
    DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" xcrun simctl list runtimes 2>/dev/null | grep -i "iOS" || true
  fi
}
# 封装 show_existing_runtimes 对应的独立处理逻辑。
show_existing_runtimes() {
  section "现有 iOS Runtime"

  local runtimes=""
  runtimes="$(list_ios_runtimes)"

  if [[ -n "$runtimes" ]]; then
    ok "检测到 iOS Runtime："
    printf "%s\n" "$runtimes"
  else
    warn "未检测到 iOS Runtime，稍后建议执行下载。"
  fi
}
# 执行已经拆分完成的独立业务步骤。
run_download() {
  section "下载 / 补齐 iOS Simulator Runtime"

  mkdir -p "$LOG_DIR"

  cecho "$C_GRAY" "日志文件：$LOG_FILE"
  cecho "$C_GRAY" "将执行：xcodebuild -downloadPlatform iOS $VERBOSE_ARG"
  echo ""

  if ! ask_run "是否开始下载 / 补齐 iOS Simulator Runtime"; then
    log "已跳过下载。"
    return 0
  fi

  local -a args
  args=(-downloadPlatform iOS "$VERBOSE_ARG")

  set +e
  DEVELOPER_DIR="$DEVELOPER_DIR_SELECTED" "$XCODEBUILD_BIN" "${args[@]}" 2>&1 | tee "$LOG_FILE"
  local command_status=${pipestatus[1]}
  set -e

  if (( command_status != 0 )); then
    err "下载命令失败，退出码：$command_status"
    warn "完整日志：$LOG_FILE"
    warn "常见原因：license 未同意、Xcode 未完成首次启动、网络 / CDN 异常、磁盘空间不足、Xcode 版本过旧。"
    exit "$command_status"
  fi

  ok "iOS Simulator Runtime 下载 / 补齐命令执行完成。"
}
# 封装 final_report 对应的独立处理逻辑。
final_report() {
  section "完成报告"

  ok "脚本执行结束。"
  cecho "$C_GRAY" "脚本路径：$SCRIPT_PATH"
  cecho "$C_GRAY" "日志路径：$LOG_FILE"
  echo ""
  cecho "$C_GREEN" "当前 iOS Runtime："
  list_ios_runtimes || true
  echo ""
  cecho "$C_GRAY" "如果 Xcode UI 里暂时看不到新 runtime，重启 Xcode 后再看。"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -R zsh
  set -eu
  set -o pipefail
  setopt NULL_GLOB
}
# 编排脚本的高层业务流程。
main() {
  show_readme_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  require_macos # 执行 require_macos 对应的独立业务步骤。
  choose_xcode_app # 执行 choose_xcode_app 对应的独立业务步骤。
  maybe_check_xcode_update # 检查当前环境与执行条件是否满足脚本要求。
  prepare_developer_dir # 执行 prepare_developer_dir 对应的独立业务步骤。
  show_xcode_version # 执行 show_xcode_version 对应的独立业务步骤。
  check_xcodebuild_support # 检查当前环境与执行条件是否满足脚本要求。
  ensure_first_launch # 检查当前环境与执行条件是否满足脚本要求。
  ensure_license # 检查当前环境与执行条件是否满足脚本要求。
  check_disk_space # 检查当前环境与执行条件是否满足脚本要求。
  check_network # 检查当前环境与执行条件是否满足脚本要求。
  show_existing_runtimes # 执行 show_existing_runtimes 对应的核心业务步骤。
  run_download # 执行 run_download 对应的核心业务步骤。
  final_report # 执行 final_report 对应的独立业务步骤。
  pause_enter "按回车退出..." # 执行 pause_enter 对应的独立业务步骤。
}

main "$@"
