#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】♻️放回本地Pod的podspec.command
# - 核心用途：执行“♻️放回本地Pod的podspec”对应的移动端项目自动化任务。
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
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
# 检查当前终端与调用环境，决定是否允许提示样式。
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
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
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
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
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0 jobs_prompt_question=0
  case "${1:-0}" in 1|--question) jobs_prompt_question=1 ;; esac
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 "$((1 - jobs_prompt_question))" "$jobs_prompt_question"
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous="" jobs_prompt_question=0
  if [ "${1:-}" = --question ]; then jobs_prompt_question=1; shift; fi
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
      "$@" 2>&1 | jobs_prompt_filter "$jobs_prompt_question" >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter "$jobs_prompt_question"
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
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
  ' | jobs_prompt_filter
}
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

LOCAL_PODS_DIR=''
PODSPEC_SOURCE_DIR=''
TARGET_INDEX_FILE=''
SOURCE_INDEX_FILE=''
TARGET_REAL_PATH_LIST=''
SOURCE_REAL_PATH_LIST=''
PROCESSED_PODSPEC_NAME_LIST=''

PODSPEC_REPLACED_COUNT=0
PODSPEC_SKIPPED_COUNT=0
JOBS_KIT_REPLACED_COUNT=0
JOBS_KIT_SKIPPED_COUNT=0
PODFILE_REPLACED_COUNT=0
PODFILE_SKIPPED_COUNT=0
# 展示脚本用途和影响范围，并在执行前等待用户确认。
print_intro() {
    printf "${BLUE}============================================================${NC}\n" | jobs_intro_style title
    printf "${BLUE} 放回本地 Pod 的 CocoaPods 相关文件${NC}\n" | jobs_intro_style title
    printf "${BLUE}============================================================${NC}\n" | jobs_intro_style title
    printf "\n" | jobs_intro_style body
    printf "功能说明：\n" | jobs_intro_style body
    printf "1. 第一步拖入管理本地 Pod 的文件夹。脚本会在该目录下最多向下一层查找 .podspec。\n" | jobs_intro_style body
    printf "2. 第二步拖入装有 .podspec 的文件夹。脚本会读取该目录直接包含的 .podspec，以及一级子文件夹里的 .podspec。\n" | jobs_intro_style body
    printf "3. 脚本会按 .podspec 文件名精确匹配，把来源 .podspec 放回本地 Pod 目录中已有的同名 .podspec。\n" | jobs_intro_style body
    printf "4. 如果来源 .podspec 同目录存在 JobsPodspecKit.rb，会同步放回到目标 .podspec 同目录：目标已有则覆盖，目标没有则创建。\n" | jobs_intro_style body
    printf "5. 不会创建新的 .podspec、Podfile、Podfile.deps、Podfile.lock；这些文件只替换已经存在的同名目标文件。\n" | jobs_intro_style body
    printf "6. Podfile、Podfile.deps、Podfile.lock 会逐个询问：直接回车跳过，输入任意字符后回车才替换。\n" | jobs_intro_style body | jobs_prompt_filter
    printf "7. Podfile 三件套默认从本地 Pod 管理目录的上层目录寻找；默认位置不存在时，会要求你拖入目标文件或包含目标文件的文件夹。\n" | jobs_intro_style body
    printf "8. 支持拖入路径中的空格、引号、反斜杠转义、~，并会尽量解析 Finder 替身和 Unix 软链接。\n" | jobs_intro_style body
    printf "\n" | jobs_intro_style body
    printf "${YELLOW}按回车开始执行...${NC}" | jobs_intro_style body | jobs_prompt_filter 1
    read -r USER_CONFIRM
    printf "\n" | jobs_intro_style body
}
# 检查当前运行条件是否满足后续流程要求。
is_blank_input() {
    local INPUT_TEXT="$1"
    local COMPACT_TEXT

    COMPACT_TEXT="$(printf '%s' "$INPUT_TEXT" | tr -d '[:space:]')"
    [ -z "$COMPACT_TEXT" ]
}
# 封装 normalize_dragged_path 对应的独立处理逻辑。
normalize_dragged_path() {
    local RAW_PATH="$1"

    RAW_PATH="$(printf '%s' "$RAW_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    RAW_PATH="${RAW_PATH%\"}"
    RAW_PATH="${RAW_PATH#\"}"
    RAW_PATH="${RAW_PATH%\'}"
    RAW_PATH="${RAW_PATH#\'}"

    RAW_PATH="$(printf '%s\n' "$RAW_PATH" | sed 's/\\\(.\)/\1/g')"

    if [ "$RAW_PATH" = "~" ]; then
        RAW_PATH="$HOME"
    elif [[ "$RAW_PATH" == "~/"* ]]; then
        RAW_PATH="$HOME/${RAW_PATH#~/}"
    fi

    printf '%s\n' "$RAW_PATH"
}
# 封装 canonicalize_path 对应的独立处理逻辑。
canonicalize_path() {
    local INPUT_PATH="$1"
    local DIR_NAME
    local BASE_NAME

    if [ -d "$INPUT_PATH" ]; then
        (
            cd "$INPUT_PATH" 2>/dev/null && pwd -P
        ) || printf '%s\n' "$INPUT_PATH"
        return
    fi

    if [ -e "$INPUT_PATH" ] || [ -L "$INPUT_PATH" ]; then
        DIR_NAME="$(dirname "$INPUT_PATH")"
        BASE_NAME="$(basename "$INPUT_PATH")"
        (
            cd "$DIR_NAME" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$BASE_NAME"
        ) || printf '%s\n' "$INPUT_PATH"
        return
    fi

    printf '%s\n' "$INPUT_PATH"
}
# 解析并返回后续流程需要的目标信息。
resolve_unix_symlink_path() {
    local INPUT_PATH="$1"
    local LINK_TARGET
    local LINK_DIR

    if [ ! -L "$INPUT_PATH" ]; then
        printf '%s\n' "$INPUT_PATH"
        return
    fi

    LINK_TARGET="$(readlink "$INPUT_PATH" 2>/dev/null)"

    if [ -z "$LINK_TARGET" ]; then
        printf '%s\n' "$INPUT_PATH"
        return
    fi

    if [[ "$LINK_TARGET" != /* ]]; then
        LINK_DIR="$(dirname "$INPUT_PATH")"
        LINK_TARGET="$LINK_DIR/$LINK_TARGET"
    fi

    canonicalize_path "$LINK_TARGET"
}
# 解析并返回后续流程需要的目标信息。
resolve_finder_alias_path() {
    local INPUT_PATH="$1"
    local RESOLVED_PATH

    RESOLVED_PATH="$(osascript - "$INPUT_PATH" <<'APPLESCRIPT' 2>/dev/null
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

    if [ -n "$RESOLVED_PATH" ]; then
        printf '%s\n' "$RESOLVED_PATH"
    else
        printf '%s\n' "$INPUT_PATH"
    fi
}
# 解析并返回后续流程需要的目标信息。
resolve_real_path() {
    local INPUT_PATH="$1"
    local CURRENT_PATH
    local NEXT_PATH
    local INDEX

    CURRENT_PATH="$(canonicalize_path "$INPUT_PATH")"
    INDEX=0

    while [ "$INDEX" -lt 10 ]; do
        NEXT_PATH="$(resolve_unix_symlink_path "$CURRENT_PATH")"
        NEXT_PATH="$(resolve_finder_alias_path "$NEXT_PATH")"
        NEXT_PATH="$(canonicalize_path "$NEXT_PATH")"

        if [ "$NEXT_PATH" = "$CURRENT_PATH" ]; then
            break
        fi

        CURRENT_PATH="$NEXT_PATH"
        INDEX=$((INDEX + 1))
    done

    printf '%s\n' "$CURRENT_PATH"
}
# 解析并返回后续流程需要的目标信息。
resolve_dragged_path() {
    resolve_real_path "$1"
}
# 封装 read_local_pods_dir 对应的独立处理逻辑。
read_local_pods_dir() {
    local RAW_PATH
    local NORMALIZED_PATH

    while true; do
        jobs_prompt_output --question echo "请把管理本地 Pod 的文件夹拖到这里，然后按回车："
        read -r RAW_PATH

        if is_blank_input "$RAW_PATH"; then
            printf "${RED}错误：输入不能为空，也不能只输入空格。${NC}\n\n" >&2
            continue
        fi

        NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"
        NORMALIZED_PATH="$(resolve_dragged_path "$NORMALIZED_PATH")"

        if [ -d "$NORMALIZED_PATH" ]; then
            LOCAL_PODS_DIR="$NORMALIZED_PATH"
            printf "${GREEN}已解析本地 Pod 管理目录：%s${NC}\n\n" "$LOCAL_PODS_DIR"
            break
        fi

        printf "${RED}错误：路径不存在，或者不是文件夹：${NC}\n"
        echo "$NORMALIZED_PATH"
        echo "请重新输入。"
        echo ""
    done
}
# 封装 read_podspec_source_dir 对应的独立处理逻辑。
read_podspec_source_dir() {
    local RAW_PATH
    local NORMALIZED_PATH

    while true; do
        jobs_prompt_output --question echo "请把装有 .podspec 的文件夹拖到这里，然后按回车："
        read -r RAW_PATH

        if is_blank_input "$RAW_PATH"; then
            printf "${RED}错误：输入不能为空，也不能只输入空格。${NC}\n\n"
            continue
        fi

        NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"
        NORMALIZED_PATH="$(resolve_dragged_path "$NORMALIZED_PATH")"

        if [ -d "$NORMALIZED_PATH" ]; then
            PODSPEC_SOURCE_DIR="$NORMALIZED_PATH"
            printf "${GREEN}已解析待放回目录：%s${NC}\n\n" "$PODSPEC_SOURCE_DIR"
            break
        fi

        printf "${RED}错误：路径不存在，或者不是文件夹：${NC}\n"
        echo "$NORMALIZED_PATH"
        echo "请重新输入。"
        echo ""
    done
}
# 封装 create_temp_files 对应的独立处理逻辑。
create_temp_files() {
    TARGET_INDEX_FILE="$(mktemp '/tmp/restore_podspec_target_index.XXXXXX')"
    SOURCE_INDEX_FILE="$(mktemp '/tmp/restore_podspec_source_index.XXXXXX')"
    TARGET_REAL_PATH_LIST="$(mktemp '/tmp/restore_podspec_target_real.XXXXXX')"
    SOURCE_REAL_PATH_LIST="$(mktemp '/tmp/restore_podspec_source_real.XXXXXX')"
    PROCESSED_PODSPEC_NAME_LIST="$(mktemp '/tmp/restore_podspec_processed_names.XXXXXX')"
}
# 执行对应的清理操作，并保留必要的安全检查。
cleanup_temp_files() {
    [ -n "$TARGET_INDEX_FILE" ] && [ -f "$TARGET_INDEX_FILE" ] && rm -f "$TARGET_INDEX_FILE"
    [ -n "$SOURCE_INDEX_FILE" ] && [ -f "$SOURCE_INDEX_FILE" ] && rm -f "$SOURCE_INDEX_FILE"
    [ -n "$TARGET_REAL_PATH_LIST" ] && [ -f "$TARGET_REAL_PATH_LIST" ] && rm -f "$TARGET_REAL_PATH_LIST"
    [ -n "$SOURCE_REAL_PATH_LIST" ] && [ -f "$SOURCE_REAL_PATH_LIST" ] && rm -f "$SOURCE_REAL_PATH_LIST"
    [ -n "$PROCESSED_PODSPEC_NAME_LIST" ] && [ -f "$PROCESSED_PODSPEC_NAME_LIST" ] && rm -f "$PROCESSED_PODSPEC_NAME_LIST"
}
# 检查当前运行条件是否满足后续流程要求。
is_path_within_one_child_level() {
    local ROOT_DIR="$1"
    local INPUT_PATH="$2"
    local ROOT_PREFIX
    local RELATIVE_PATH

    ROOT_PREFIX="${ROOT_DIR%/}/"
    RELATIVE_PATH="${INPUT_PATH#$ROOT_PREFIX}"

    if [ "$RELATIVE_PATH" = "$INPUT_PATH" ]; then
        return 1
    fi

    case "$RELATIVE_PATH" in
        */*/*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}
# 检查当前运行条件是否满足后续流程要求。
has_recorded_real_path() {
    local LIST_FILE="$1"
    local REAL_PATH="$2"

    [ -f "$LIST_FILE" ] && grep -F -x -q -- "$REAL_PATH" "$LIST_FILE"
}
# 封装 record_real_path 对应的独立处理逻辑。
record_real_path() {
    local LIST_FILE="$1"
    local REAL_PATH="$2"

    printf '%s\n' "$REAL_PATH" >> "$LIST_FILE"
}
# 封装 append_index_record 对应的独立处理逻辑。
append_index_record() {
    local INDEX_FILE="$1"
    local FILE_NAME="$2"
    local FILE_PATH="$3"

    printf '%s\t%s\n' "$FILE_NAME" "$FILE_PATH" >> "$INDEX_FILE"
}
# 封装 build_target_podspec_index 对应的独立处理逻辑。
build_target_podspec_index() {
    local PODSPEC_FILE
    local REAL_PODSPEC_FILE
    local PODSPEC_NAME

    : > "$TARGET_INDEX_FILE"
    : > "$TARGET_REAL_PATH_LIST"

    while IFS= read -r PODSPEC_FILE; do
        if ! is_path_within_one_child_level "$LOCAL_PODS_DIR" "$PODSPEC_FILE"; then
            continue
        fi

        REAL_PODSPEC_FILE="$(resolve_real_path "$PODSPEC_FILE")"

        if [ ! -f "$REAL_PODSPEC_FILE" ]; then
            continue
        fi

        if has_recorded_real_path "$TARGET_REAL_PATH_LIST" "$REAL_PODSPEC_FILE"; then
            continue
        fi

        PODSPEC_NAME="$(basename "$REAL_PODSPEC_FILE")"
        append_index_record "$TARGET_INDEX_FILE" "$PODSPEC_NAME" "$REAL_PODSPEC_FILE"
        record_real_path "$TARGET_REAL_PATH_LIST" "$REAL_PODSPEC_FILE"
    done < <(find "$LOCAL_PODS_DIR" \( -type f -o -type l \) -iname '*.podspec' -print 2>/dev/null)
}
# 封装 build_source_podspec_index 对应的独立处理逻辑。
build_source_podspec_index() {
    local PODSPEC_FILE
    local REAL_PODSPEC_FILE
    local PODSPEC_NAME

    : > "$SOURCE_INDEX_FILE"
    : > "$SOURCE_REAL_PATH_LIST"

    while IFS= read -r PODSPEC_FILE; do
        if ! is_path_within_one_child_level "$PODSPEC_SOURCE_DIR" "$PODSPEC_FILE"; then
            continue
        fi

        REAL_PODSPEC_FILE="$(resolve_real_path "$PODSPEC_FILE")"

        if [ ! -f "$REAL_PODSPEC_FILE" ]; then
            continue
        fi

        if has_recorded_real_path "$SOURCE_REAL_PATH_LIST" "$REAL_PODSPEC_FILE"; then
            continue
        fi

        PODSPEC_NAME="$(basename "$REAL_PODSPEC_FILE")"
        append_index_record "$SOURCE_INDEX_FILE" "$PODSPEC_NAME" "$REAL_PODSPEC_FILE"
        record_real_path "$SOURCE_REAL_PATH_LIST" "$REAL_PODSPEC_FILE"
    done < <(find "$PODSPEC_SOURCE_DIR" \( -type f -o -type l \) -iname '*.podspec' -print 2>/dev/null)
}
# 解析并返回后续流程需要的目标信息。
get_index_count_by_name() {
    local INDEX_FILE="$1"
    local FILE_NAME="$2"

    awk -F '\t' -v fileName="$FILE_NAME" '$1 == fileName { count++ } END { print count + 0 }' "$INDEX_FILE"
}
# 解析并返回后续流程需要的目标信息。
get_index_first_path_by_name() {
    local INDEX_FILE="$1"
    local FILE_NAME="$2"

    awk -F '\t' -v fileName="$FILE_NAME" '$1 == fileName { print $2; exit }' "$INDEX_FILE"
}
# 解析并返回后续流程需要的目标信息。
get_index_total_count() {
    local INDEX_FILE="$1"

    wc -l < "$INDEX_FILE" | tr -d '[:space:]'
}
# 检查当前运行条件是否满足后续流程要求。
has_processed_podspec_name() {
    local PODSPEC_NAME="$1"

    [ -f "$PROCESSED_PODSPEC_NAME_LIST" ] && grep -F -x -q -- "$PODSPEC_NAME" "$PROCESSED_PODSPEC_NAME_LIST"
}
# 封装 record_processed_podspec_name 对应的独立处理逻辑。
record_processed_podspec_name() {
    local PODSPEC_NAME="$1"

    printf '%s\n' "$PODSPEC_NAME" >> "$PROCESSED_PODSPEC_NAME_LIST"
}
# 封装 replace_existing_file 对应的独立处理逻辑。
replace_existing_file() {
    local SOURCE_FILE="$1"
    local TARGET_FILE="$2"
    local DISPLAY_NAME="$3"
    local REAL_SOURCE_FILE
    local REAL_TARGET_FILE

    REAL_SOURCE_FILE="$(resolve_real_path "$SOURCE_FILE")"
    REAL_TARGET_FILE="$(resolve_real_path "$TARGET_FILE")"

    if [ ! -f "$REAL_SOURCE_FILE" ]; then
        printf "${RED}跳过：来源不是文件：%s${NC}\n" "$SOURCE_FILE"
        return 1
    fi

    if [ ! -f "$REAL_TARGET_FILE" ]; then
        printf "${RED}跳过：目标不存在，或者目标不是文件：%s${NC}\n" "$TARGET_FILE"
        return 1
    fi

    if cp -p "$REAL_SOURCE_FILE" "$REAL_TARGET_FILE"; then
        printf "${GREEN}已替换：%s${NC}\n" "$DISPLAY_NAME"
        echo "  来源：$REAL_SOURCE_FILE"
        echo "  目标：$REAL_TARGET_FILE"
        return 0
    fi

    printf "${RED}替换失败：%s${NC}\n" "$DISPLAY_NAME"
    echo "  来源：$REAL_SOURCE_FILE"
    echo "  目标：$REAL_TARGET_FILE"
    return 1
}
# 封装 restore_jobs_podspec_kit_for_podspec 对应的独立处理逻辑。
restore_jobs_podspec_kit_for_podspec() {
    local SOURCE_PODSPEC_FILE="$1"
    local TARGET_PODSPEC_FILE="$2"
    local SOURCE_KIT_FILE
    local TARGET_KIT_FILE
    local REAL_SOURCE_KIT_FILE
    local REAL_TARGET_KIT_FILE

    SOURCE_KIT_FILE="$(dirname "$SOURCE_PODSPEC_FILE")/JobsPodspecKit.rb"

    if [ ! -e "$SOURCE_KIT_FILE" ] && [ ! -L "$SOURCE_KIT_FILE" ]; then
        return 0
    fi

    REAL_SOURCE_KIT_FILE="$(resolve_real_path "$SOURCE_KIT_FILE")"

    if [ ! -f "$REAL_SOURCE_KIT_FILE" ]; then
        printf "${RED}跳过 JobsPodspecKit.rb：来源不是文件：%s${NC}\n" "$SOURCE_KIT_FILE"
        JOBS_KIT_SKIPPED_COUNT=$((JOBS_KIT_SKIPPED_COUNT + 1))
        return 1
    fi

    TARGET_KIT_FILE="$(dirname "$TARGET_PODSPEC_FILE")/JobsPodspecKit.rb"

    if [ -e "$TARGET_KIT_FILE" ] || [ -L "$TARGET_KIT_FILE" ]; then
        REAL_TARGET_KIT_FILE="$(resolve_real_path "$TARGET_KIT_FILE")"

        if [ ! -f "$REAL_TARGET_KIT_FILE" ]; then
            printf "${YELLOW}跳过 JobsPodspecKit.rb：目标路径存在，但不是文件，不做替换。${NC}\n"
            echo "  目标：$TARGET_KIT_FILE"
            JOBS_KIT_SKIPPED_COUNT=$((JOBS_KIT_SKIPPED_COUNT + 1))
            return 1
        fi

        if replace_existing_file "$REAL_SOURCE_KIT_FILE" "$REAL_TARGET_KIT_FILE" "JobsPodspecKit.rb"; then
            JOBS_KIT_REPLACED_COUNT=$((JOBS_KIT_REPLACED_COUNT + 1))
            return 0
        fi
    else
        if cp -p "$REAL_SOURCE_KIT_FILE" "$TARGET_KIT_FILE"; then
            printf "${GREEN}已创建：JobsPodspecKit.rb${NC}\n"
            echo "  来源：$REAL_SOURCE_KIT_FILE"
            echo "  目标：$TARGET_KIT_FILE"
            JOBS_KIT_REPLACED_COUNT=$((JOBS_KIT_REPLACED_COUNT + 1))
            return 0
        fi

        printf "${RED}创建失败：JobsPodspecKit.rb${NC}\n"
        echo "  来源：$REAL_SOURCE_KIT_FILE"
        echo "  目标：$TARGET_KIT_FILE"
    fi

    JOBS_KIT_SKIPPED_COUNT=$((JOBS_KIT_SKIPPED_COUNT + 1))
    return 1
}
# 封装 restore_podspec_files 对应的独立处理逻辑。
restore_podspec_files() {
    local SOURCE_NAME
    local SOURCE_FILE
    local SOURCE_COUNT
    local TARGET_COUNT
    local TARGET_FILE

    printf "${BLUE}开始按同名 .podspec 放回本地 Pod 目录...${NC}\n"

    if [ "$(get_index_total_count "$SOURCE_INDEX_FILE")" -eq 0 ]; then
        printf "${RED}待放回目录中没有找到符合层级要求的 .podspec。${NC}\n"
        return 0
    fi

    if [ "$(get_index_total_count "$TARGET_INDEX_FILE")" -eq 0 ]; then
        printf "${RED}本地 Pod 管理目录中没有找到符合层级要求的 .podspec。${NC}\n"
        return 0
    fi

    while IFS="$(printf '\t')" read -r SOURCE_NAME SOURCE_FILE; do
        if [ -z "$SOURCE_NAME" ] || [ -z "$SOURCE_FILE" ]; then
            continue
        fi

        if has_processed_podspec_name "$SOURCE_NAME"; then
            continue
        fi

        record_processed_podspec_name "$SOURCE_NAME"

        SOURCE_COUNT="$(get_index_count_by_name "$SOURCE_INDEX_FILE" "$SOURCE_NAME")"
        TARGET_COUNT="$(get_index_count_by_name "$TARGET_INDEX_FILE" "$SOURCE_NAME")"

        if [ "$SOURCE_COUNT" -gt 1 ]; then
            printf "${YELLOW}跳过：待放回目录中存在多个同名 .podspec，无法安全判断来源：%s${NC}\n" "$SOURCE_NAME"
            PODSPEC_SKIPPED_COUNT=$((PODSPEC_SKIPPED_COUNT + 1))
            continue
        fi

        if [ "$TARGET_COUNT" -eq 0 ]; then
            printf "${YELLOW}跳过：本地 Pod 目录中不存在同名目标 .podspec：%s${NC}\n" "$SOURCE_NAME"
            PODSPEC_SKIPPED_COUNT=$((PODSPEC_SKIPPED_COUNT + 1))
            continue
        fi

        if [ "$TARGET_COUNT" -gt 1 ]; then
            printf "${YELLOW}跳过：本地 Pod 目录中存在多个同名目标 .podspec，避免误替换：%s${NC}\n" "$SOURCE_NAME"
            PODSPEC_SKIPPED_COUNT=$((PODSPEC_SKIPPED_COUNT + 1))
            continue
        fi

        TARGET_FILE="$(get_index_first_path_by_name "$TARGET_INDEX_FILE" "$SOURCE_NAME")"

        if replace_existing_file "$SOURCE_FILE" "$TARGET_FILE" "$SOURCE_NAME"; then
            PODSPEC_REPLACED_COUNT=$((PODSPEC_REPLACED_COUNT + 1))
            restore_jobs_podspec_kit_for_podspec "$SOURCE_FILE" "$TARGET_FILE"
        else
            PODSPEC_SKIPPED_COUNT=$((PODSPEC_SKIPPED_COUNT + 1))
        fi
    done < "$SOURCE_INDEX_FILE"
}
# 收集并校验用户输入，决定后续执行路径。
ask_should_replace() {
    local FILE_NAME="$1"
    local USER_INPUT

    jobs_prompt_output --question printf "${YELLOW}是否替换 %s？直接回车 = 跳过，输入任意字符后回车 = 替换：${NC}" "$FILE_NAME"
    read -r USER_INPUT

    if is_blank_input "$USER_INPUT"; then
        return 1
    fi

    return 0
}
# 解析并返回后续流程需要的目标信息。
resolve_default_podfile_target() {
    local PODFILE_NAME="$1"
    local LOCAL_PARENT_DIR
    local TARGET_FILE
    local REAL_TARGET_FILE

    LOCAL_PARENT_DIR="$(dirname "$LOCAL_PODS_DIR")"
    TARGET_FILE="$LOCAL_PARENT_DIR/$PODFILE_NAME"

    if [ -e "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ]; then
        REAL_TARGET_FILE="$(resolve_real_path "$TARGET_FILE")"
        if [ -f "$REAL_TARGET_FILE" ]; then
            printf '%s\n' "$REAL_TARGET_FILE"
            return 0
        fi
    fi

    return 1
}
# 封装 read_podfile_target_path 对应的独立处理逻辑。
read_podfile_target_path() {
    local PODFILE_NAME="$1"
    local RAW_PATH
    local NORMALIZED_PATH
    local CANDIDATE_FILE
    local REAL_CANDIDATE_FILE

    while true; do
        jobs_prompt_output --question echo "请拖入目标 $PODFILE_NAME 文件，或者拖入包含 $PODFILE_NAME 的文件夹，然后按回车：" >&2
        read -r RAW_PATH

        if is_blank_input "$RAW_PATH"; then
            printf "${RED}错误：输入不能为空，也不能只输入空格。${NC}\n\n" >&2
            continue
        fi

        NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"
        NORMALIZED_PATH="$(resolve_dragged_path "$NORMALIZED_PATH")"
        CANDIDATE_FILE=''

        if [ -d "$NORMALIZED_PATH" ]; then
            CANDIDATE_FILE="$NORMALIZED_PATH/$PODFILE_NAME"
        elif [ -e "$NORMALIZED_PATH" ] || [ -L "$NORMALIZED_PATH" ]; then
            if [ "$(basename "$NORMALIZED_PATH")" = "$PODFILE_NAME" ]; then
                CANDIDATE_FILE="$NORMALIZED_PATH"
            else
                printf "${RED}错误：拖入的是文件，但文件名不是 %s。${NC}\n\n" "$PODFILE_NAME" >&2
                continue
            fi
        else
            printf "${RED}错误：路径不存在：%s${NC}\n\n" "$NORMALIZED_PATH" >&2
            continue
        fi

        if [ -e "$CANDIDATE_FILE" ] || [ -L "$CANDIDATE_FILE" ]; then
            REAL_CANDIDATE_FILE="$(resolve_real_path "$CANDIDATE_FILE")"
            if [ -f "$REAL_CANDIDATE_FILE" ]; then
                printf '%s\n' "$REAL_CANDIDATE_FILE"
                return 0
            fi
        fi

        printf "${RED}错误：目标目录下面不存在同名文件，不会创建新文件：%s${NC}\n\n" "$CANDIDATE_FILE" >&2
    done
}
# 封装 restore_podfile_by_name 对应的独立处理逻辑。
restore_podfile_by_name() {
    local PODFILE_NAME="$1"
    local SOURCE_FILE
    local REAL_SOURCE_FILE
    local TARGET_FILE

    SOURCE_FILE="$PODSPEC_SOURCE_DIR/$PODFILE_NAME"

    if [ ! -e "$SOURCE_FILE" ] && [ ! -L "$SOURCE_FILE" ]; then
        printf "${YELLOW}待放回目录中没有找到 %s，跳过。${NC}\n" "$PODFILE_NAME"
        PODFILE_SKIPPED_COUNT=$((PODFILE_SKIPPED_COUNT + 1))
        return 0
    fi

    REAL_SOURCE_FILE="$(resolve_real_path "$SOURCE_FILE")"

    if [ ! -f "$REAL_SOURCE_FILE" ]; then
        printf "${YELLOW}待放回目录中的 %s 不是文件，跳过。${NC}\n" "$PODFILE_NAME"
        echo "  来源：$SOURCE_FILE"
        PODFILE_SKIPPED_COUNT=$((PODFILE_SKIPPED_COUNT + 1))
        return 0
    fi

    if ! ask_should_replace "$PODFILE_NAME"; then
        printf "${YELLOW}已跳过：%s${NC}\n" "$PODFILE_NAME"
        PODFILE_SKIPPED_COUNT=$((PODFILE_SKIPPED_COUNT + 1))
        return 0
    fi

    TARGET_FILE="$(resolve_default_podfile_target "$PODFILE_NAME")"

    if [ -z "$TARGET_FILE" ]; then
        printf "${YELLOW}默认位置不存在 %s：%s${NC}\n" "$PODFILE_NAME" "$(dirname "$LOCAL_PODS_DIR")/$PODFILE_NAME"
        TARGET_FILE="$(read_podfile_target_path "$PODFILE_NAME")"
    else
        printf "${GREEN}已找到默认目标：%s${NC}\n" "$TARGET_FILE"
    fi

    if replace_existing_file "$REAL_SOURCE_FILE" "$TARGET_FILE" "$PODFILE_NAME"; then
        PODFILE_REPLACED_COUNT=$((PODFILE_REPLACED_COUNT + 1))
    else
        PODFILE_SKIPPED_COUNT=$((PODFILE_SKIPPED_COUNT + 1))
    fi
}
# 封装 restore_podfiles 对应的独立处理逻辑。
restore_podfiles() {
    echo ""
    printf "${BLUE}开始处理 Podfile / Podfile.deps / Podfile.lock...${NC}\n"

    restore_podfile_by_name "Podfile.deps"
    restore_podfile_by_name "Podfile"
    restore_podfile_by_name "Podfile.lock"
}
# 封装 print_index_summary 对应的独立处理逻辑。
print_index_summary() {
    echo ""
    printf "${BLUE}扫描结果：${NC}\n"
    echo "本地 Pod 目录中可匹配的 .podspec：$(get_index_total_count "$TARGET_INDEX_FILE") 个"
    echo "待放回目录中可匹配的 .podspec：$(get_index_total_count "$SOURCE_INDEX_FILE") 个"
    echo ""
}
# 封装 print_result 对应的独立处理逻辑。
print_result() {
    echo ""
    printf "${GREEN}执行完成。${NC}\n"
    echo ".podspec 已替换：$PODSPEC_REPLACED_COUNT 个"
    echo ".podspec 已跳过：$PODSPEC_SKIPPED_COUNT 个"
    echo "JobsPodspecKit.rb 已替换：$JOBS_KIT_REPLACED_COUNT 个"
    echo "JobsPodspecKit.rb 已跳过：$JOBS_KIT_SKIPPED_COUNT 个"
    echo "Podfile 三件套已替换：$PODFILE_REPLACED_COUNT 个"
    echo "Podfile 三件套已跳过：$PODFILE_SKIPPED_COUNT 个"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】♻️放回本地Pod的podspec.command' | jobs_intro_style title
  print -r -- '核心用途：执行“♻️放回本地Pod的podspec”对应的移动端项目自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 130
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
    # 注册退出处理，确保异常中断时仍能执行必要收尾。
    trap cleanup_temp_files EXIT

    # 执行当前流程中的独立业务步骤：print_intro。
    print_intro
    # 执行当前流程中的独立业务步骤：read_local_pods_dir。
    read_local_pods_dir
    # 执行当前流程中的独立业务步骤：read_podspec_source_dir。
    read_podspec_source_dir

    # 执行当前流程中的独立业务步骤：create_temp_files。
    create_temp_files
    # 执行当前流程中的独立业务步骤：build_target_podspec_index。
    build_target_podspec_index
    # 执行当前流程中的独立业务步骤：build_source_podspec_index。
    build_source_podspec_index
    # 输出当前流程的完成状态、摘要和日志位置。
    print_index_summary

    # 执行当前流程中的独立业务步骤：restore_podspec_files。
    restore_podspec_files
    # 执行当前流程中的独立业务步骤：restore_podfiles。
    restore_podfiles
    # 执行当前流程中的独立业务步骤：print_result。
    print_result
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -u
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示用途与影响，并按当前入口完成防误触确认。
  initialize_script_runtime # 确认后初始化日志、Shell 选项与本次运行状态。
  run_main_business_flow "$@" # 执行当前工具的选择、确认与业务处理。
}

main "$@"
