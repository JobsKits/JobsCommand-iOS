#!/bin/zsh
# ==============================================================================
# CodeX+UnderstandAnything.command
# 用途：体检 Codex 与 Understand Anything，为 Xcode/iOS 工程生成中文知识图谱。
# 边界：只在用户确认后安装或升级；不挂接 pod install，不自动分析工程。
# 风险：安装流程会下载官方安装脚本，/understand 会消耗 Codex/AI 额度。
# 日志：通过内置自述后，终端输出同步写入系统临时目录中的同名 .log 文件。
# ==============================================================================

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

# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
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

# 展示 Homebrew 获取进度，日志层保持纯文本。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  jobs_prompt_output --question print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if jobs_brew_download_file "$installer" 'Homebrew 官方安装器' \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      'https://api.github.com/repos/Homebrew/install/contents/install.sh?ref=HEAD'; then
    if [[ ! -s "$installer" || "$(head -n 1 "$installer")" != '#!/bin/bash' ]] || ! /bin/bash -n "$installer"; then
      rm -f -- "$installer"
      jobs_brew_note '官方安装器响应为空或内容校验失败（可能是 HTML / JSON 错误页）；未执行安装。'
      return 1
    fi
  else
    installer_result=$?
    rm -f -- "$installer"
    jobs_brew_note "系统目录安装器下载失败（curl 退出码 $installer_result）；尚未执行安装，不自动切换安装路径。"
    return "$installer_result"
  fi
  /bin/bash "$installer" || installer_result=$?
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return "$installer_result"
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin release_result=0
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  local git_health=1 locate_result=0 git_candidate="" selected_developer="" clt_result=0 clt_diagnostic=""
  git_bin="$(command -v git 2>/dev/null)"
  # /usr/bin/git 可能只是CLT占位器；先查询真实工具，避免健康检查自行弹出安装窗口。
  if [[ "$git_bin" == /usr/bin/git || -z "$git_bin" ]]; then
    git_bin="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  fi
  if [[ -n "$git_bin" && -x "$git_bin" ]]; then
    git_health=0;"$git_bin" --version >/dev/null 2>&1 || git_health=$?
    case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
  fi
  if (( git_health != 0 )); then
    [[ -z "${DEVELOPER_DIR:-}" ]] || { jobs_brew_note '显式DEVELOPER_DIR没有健康Git，保留用户开发目录，未自动改全局选择。'; return 1; }
    locate_result=0
    selected_developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$selected_developer" && -d "$selected_developer" ]]; then
      jobs_brew_note "既有开发目录未提供健康Git：$selected_developer；可能是许可、版本或本地文件阻塞，未反复安装或改全局xcode-select。"
      return 1
    fi
    if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 || ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]] ||
       env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
      jobs_brew_note '用户目录Homebrew需要健康Git；当前为只读或非交互入口，未打开CLT安装窗口或写安装目标。'
      return 1
    fi
    jobs_brew_note '当前已选用户目录Homebrew安装需要Apple Command Line Tools的Git；只打开一次原生安装窗口，许可由本人处理，当前流程持续复检，Ctrl+C停止。' || return $?
    clt_diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || clt_result=$?
    jobs_brew_note "$clt_diagnostic" || return $?
    if (( clt_result != 0 )) && [[ "$clt_diagnostic" != *'already being installed'* && "$clt_diagnostic" != *'正在安装'* ]]; then return "$clt_result"; fi
    while true; do
      locate_result=0
      git_candidate="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
      case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
      if [[ -n "$git_candidate" && -x "$git_candidate" ]]; then
        git_health=0;"$git_candidate" --version >/dev/null 2>&1 || git_health=$?
        case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
        if (( git_health == 0 )); then git_bin="$git_candidate";break;fi
      fi
      jobs_brew_note '等待Apple CLT提供健康Git；不会重复打开窗口，Ctrl+C停止。' || return $?
      /bin/sleep 3 || return $?
    done
  fi
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if jobs_brew_download_file "$stage/release.json" 'Homebrew 官方稳定版本' \
      https://api.github.com/repos/Homebrew/brew/releases/latest; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    rm -r -- "$stage"
    jobs_brew_note '官方版本响应无有效 tag，停止；不重试版本解析或执行安装。'
    return 1
  fi
  if jobs_brew_fetch_release "$git_bin" "$release_tag" "$stage"; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 官方版本获取已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  if ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || jobs_brew_stop_failed_install $? ;;
      user) jobs_brew_install_user || jobs_brew_stop_failed_install $? ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}

# 持续获取必需官方文件，网络失败重试，确定错误及取消停止。
jobs_brew_download_file() {
  local destination="$1" description="$2" download_url attempt download_result=1 http_code
  local retry_round=0 retry_delay=1 round_has_retryable=0
  local -a request_headers download_urls
  local -A blocked_urls
  shift 2
  download_urls=("$@")
  (( ${#download_urls} > 0 )) || { jobs_brew_note '没有已声明的官方获取地址。'; return 2; }
  while true; do
    (( retry_round += 1 ))
    round_has_retryable=0
    for download_url in "${download_urls[@]}"; do
      [[ -z "${blocked_urls[$download_url]:-}" ]] || continue
      request_headers=()
      if [[ "$download_url" == https://api.github.com/repos/Homebrew/install/contents/install.sh\?ref=HEAD ]]; then
        request_headers=(-H 'Accept: application/vnd.github.raw+json')
      fi
      for attempt in 1 2 3; do
        jobs_brew_note "下载${description}（第 $retry_round 轮，第 $attempt 次）：$download_url"
        download_result=0
        http_code="$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 30 "${request_headers[@]}" \
          --write-out '%{http_code}' "$download_url" -o "$destination" \
          2> >(tee -a "${LOG_FILE:-/dev/null}" >&2))" || download_result=$?
        if (( download_result == 0 )); then
          return 0
        fi
        rm -f -- "$destination" || return 1
        jobs_brew_note "${description}下载失败：curl 退出码 $download_result，HTTP ${http_code:-未知}。"
        case "$download_result" in
          129|130|143) return "$download_result" ;;
          5|6|7|18|28|35|52|55|56) ;;
          22)
            if [[ "$http_code" != 408 && "$http_code" != 429 && "$http_code" != 5[0-9][0-9] ]]; then
              blocked_urls[$download_url]=1
              break
            fi
            ;;
          *) blocked_urls[$download_url]=1; break ;;
        esac
        if (( attempt < 3 )); then
          jobs_brew_note '临时连接失败，1 秒后重试同一官方地址；Ctrl+C 可取消。'
          sleep 1 || return $?
        fi
      done
      if [[ -z "${blocked_urls[$download_url]:-}" ]]; then
        round_has_retryable=1
      fi
      jobs_brew_note '当前地址尚未取得可用响应；如有下一已声明官方地址，将按原顺序尝试，安装目录不变。'
    done
    if (( round_has_retryable == 0 )); then
      jobs_brew_note "获取${description}遇到确定错误，停止；未执行安装。日志：${LOG_FILE:-终端输出}。"
      return "$download_result"
    fi
    jobs_brew_note "官方来源暂时不可用，${retry_delay} 秒后继续下一轮；不设总次数或总时长上限，按 Ctrl+C 取消。"
    sleep "$retry_delay" || return $?
    if (( retry_delay < 30 )); then
      retry_delay=$(( retry_delay * 2 ))
      (( retry_delay <= 30 )) || retry_delay=30
    fi
  done
}

# 只停止当前获取器创建的子进程树，保留调用者陷阱。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}

# 持续获取明确官方稳定 tag，精确版本校验后才发布。
jobs_brew_fetch_release() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS NO_ERREXIT
  local git_bin="$1" release_tag="$2" stage="$3" target="${3}/brew"
  local attempt_log="${3}/git-fetch-attempt.log" history="${3}/git-fetch-history.log"
  local attempt=1 result=0 delay=1 task_pid="" interrupted=0 failure=""
  [[ "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$stage" == /* &&
     "${stage:t}" == .jobs-homebrew.* && -d "$stage" && ! -L "$stage" && ! -e "$target" && ! -L "$target" ]] || {
    jobs_brew_note 'Homebrew 获取版本或私有暂存路径无效，未执行 Git 获取。'
    return 2
  }
  "$git_bin" init --quiet "$target" || { result=$?; jobs_brew_note "Homebrew 暂存仓初始化失败（$result）：$target"; return "$result"; }
  "$git_bin" -C "$target" remote add origin https://github.com/Homebrew/brew.git || return $?
  trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' INT
  trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' TERM
  trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' HUP
  while true; do
    jobs_brew_note "获取 Homebrew 官方版本 $release_tag（第 $attempt 次）：https://github.com/Homebrew/brew.git → $target；失败自动重试，Ctrl+C 取消。"
    : > "$attempt_log" || return 1
    print -r -- "━━ Homebrew $release_tag：第 $attempt 次 ━━" >> "$history" || return 1
    (
      local -a acquisition_statuses
      LC_ALL=C GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$target" -c color.ui=false \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 fetch --progress --depth 1 origin "refs/tags/$release_tag" 2>&1 |
        jobs_prompt_tee "$history" | jobs_prompt_tee "${LOG_FILE:-/dev/null}" | jobs_prompt_tee "$attempt_log" >&2
      acquisition_statuses=("${pipestatus[@]}")
      (( acquisition_statuses[2] == 0 && acquisition_statuses[3] == 0 && acquisition_statuses[4] == 0 )) || exit 74
      exit "${acquisition_statuses[1]}"
    ) <&0 &
    task_pid=$!
    result=0
    wait "$task_pid" || result=$?
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    jobs_brew_note "Homebrew $release_tag 获取第 $attempt 次退出码：$result。"
    if (( result == 0 )); then
      "$git_bin" -C "$target" checkout --quiet --detach FETCH_HEAD || return $?
      return 0
    fi
    case "$result" in
      74) jobs_brew_note "Homebrew 获取日志写入失败，停止；请检查磁盘空间、路径和权限。"; return 74 ;;
      129|130|131|137|143|126|127) return "$result" ;;
    esac
    failure="$(/usr/bin/tail -c 65536 "$attempt_log")" || return 1
    if print -r -- "$failure" | /usr/bin/grep -Eqi \
      'Permission denied|Operation not permitted|No space left on device|Read-only file system|File exists|already exists and is not an empty directory|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|couldn.t find remote ref|Remote branch .* not found|repository .* not found|Authentication failed|could not read Username|terminal prompts disabled|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed|unable to get local issuer certificate'; then
      jobs_brew_note "Homebrew 官方版本获取遇到本地、认证、证书或版本确定错误（$result），已停止；请核对日志：${LOG_FILE:-$history}。"
      return "$result"
    fi
    jobs_brew_note "Homebrew 网络获取尚未完成，保留本轮已收对象，${delay} 秒后继续；不设总次数或总时长上限，Ctrl+C 取消。"
    sleep "$delay" &
    task_pid=$!
    wait "$task_pid" || { result=$?; (( interrupted == 0 )) || return "$interrupted"; return "$result"; }
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}

# 保留获取失败和取消的原始状态，阻止后续业务。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}
# <<< Jobs Homebrew install choice <<<
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  jobs_prompt_output --question print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  jobs_prompt_output --question print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_ios_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

# 按终端能力渲染自述，纯文本环境不输出 ANSI。
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
APP_NAME="CodeX + Understand Anything"
UA_REPO="$HOME/.understand-anything/repo"
UA_INSTALL_URL="https://raw.githubusercontent.com/Lum1104/Understand-Anything/main/install.sh"

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t}"
LOG_FILE="${TMPDIR%/}/${SCRIPT_BASENAME}.log"

PROJECT_ROOT=""
typeset -ga XCODE_ITEMS=()

# 在任何落盘或联网动作前说明用途、影响和取消方式，避免双击误触。
show_script_intro_and_wait() {
  print -r -- "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- "脚本名称：${SCRIPT_BASENAME}" | jobs_intro_style title
  print -r -- "核心用途：体检 Codex 与 Understand Anything，并为指定 Xcode/iOS 工程准备代码图谱命令。" | jobs_intro_style body
  print -r -- "默认行为：确认后准备 Homebrew Python；生成图谱或启动 Codex 等动作仍单独询问。" | jobs_intro_style body
  print -r -- "可能影响：用户确认后，可能下载官方安装脚本并更新用户级 Understand Anything Skills。" | jobs_intro_style body
  print -r -- "额度提醒：真正执行 /understand 时会消耗 Codex/AI 额度，本脚本不把它挂到 pod install。" | jobs_intro_style body
  print -r -- "日志位置：确认继续后，输出写入系统临时目录中的 ${SCRIPT_BASENAME}.log。" | jobs_intro_style body
  print -r -- "取消方式：此时按 Ctrl+C 终止，不会进入后续业务。" | jobs_intro_style body
  print -r -- "============================================================================" | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前没有可交互终端，请双击脚本或在 Terminal 中运行。"
    exit 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}

# 在用户通过自述确认后再初始化严格选项与日志，避免确认前产生副作用。
initialize_script_runtime() {
  set -u
  setopt NO_NOMATCH
  : >| "$LOG_FILE"
  exec > >(jobs_prompt_tee "$LOG_FILE") 2>&1
}

# 输出带时间戳的统一日志，便于终端和日志文件交叉排查。
log() {
  jobs_prompt_output print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 输出流程分隔线，降低长路径和命令说明混在一起的阅读成本。
line() {
  print -r -- "────────────────────────────────────────────────────────────"
}

# 展示运行身份和日志位置，让用户在选择工程前确认脚本来源。
print_runtime_header() {
  clear 2>/dev/null || true
  print -r -- "🧠 ${APP_NAME}"
  print -r -- "用途：为自有或授权 Xcode/iOS 工程准备 Understand Anything 中文代码图谱"
  line
  log "脚本路径：${SCRIPT_PATH}"
  log "脚本目录：${SCRIPT_DIR}"
  log "日志文件：${LOG_FILE}"
  line
}

# 清理 Finder 拖入路径的引号、转义和 file URL，保留真实目录语义。
normalize_user_path() {
  local raw="$1"
  raw="${raw#${raw%%[![:space:]]*}}"
  raw="${raw%${raw##*[![:space:]]}}"
  raw="${(Q)raw}"
  if [[ "$raw" == file://* ]]; then
    raw="${raw#file://}"
    if [[ -x "${JOBS_PYTHON_BIN:-}" ]]; then
      raw="$("$JOBS_PYTHON_BIN" -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>/dev/null || print -r -- "$raw")"
    fi
  fi
  if [[ "$raw" == "~" || "$raw" == ~/* ]]; then
    raw="${raw/#\~/$HOME}"
  fi
  print -r -- "$raw"
}

# 判断输入是否直接指向 Xcode workspace 或 project 包。
is_xcode_item_path() {
  local target_path="$1"
  local lower="${target_path:l}"
  [[ -d "$target_path" && ( "$lower" == *.xcworkspace || "$lower" == *.xcodeproj ) ]]
}

# 只扫描候选目录第一层，避免误选 Pods、示例子工程或其它仓库。
scan_xcode_items_in_dir() {
  local dir="$1"
  local item=""
  XCODE_ITEMS=()
  [[ -d "$dir" ]] || return 1
  while IFS= read -r item; do
    [[ -n "$item" ]] && XCODE_ITEMS+=("$item")
  done < <(find "$dir" -maxdepth 1 -type d -iname "*.xcworkspace" -print 2>/dev/null | sort)
  while IFS= read -r item; do
    [[ -n "$item" ]] && XCODE_ITEMS+=("$item")
  done < <(find "$dir" -maxdepth 1 -type d -iname "*.xcodeproj" -print 2>/dev/null | sort)
  (( ${#XCODE_ITEMS[@]} > 0 ))
}

# 打印候选工程包，避免只凭目录名误判项目根目录。
print_found_xcode_items() {
  local root="$1"
  local item=""
  line
  log "✅ 找到候选 Xcode/iOS 工程根目录：${root}"
  for item in "${XCODE_ITEMS[@]}"; do
    print -r -- "  - $(basename "$item")"
  done
  line
}

# 让用户确认自动命中的目录，输入任意字符可继续寻找其它候选项。
confirm_project_root() {
  local root="$1"
  local answer=""
  print_found_xcode_items "$root"
  read -r "?$(jobs_prompt_render "直接回车确认；输入任意字符后回车继续选择：")" answer
  [[ -z "$answer" ]]
}

# 验证目录并在用户确认后写入唯一工程根目录。
try_set_project_root_from_dir() {
  local dir="$1"
  dir="${dir:A}"
  if scan_xcode_items_in_dir "$dir" && confirm_project_root "$dir"; then
    PROJECT_ROOT="$dir"
    return 0
  fi
  return 1
}

# 同时支持工程根目录、workspace 和 project 三种拖入输入。
try_set_project_root_from_input_path() {
  local candidate="$1"
  if is_xcode_item_path "$candidate"; then
    try_set_project_root_from_dir "${candidate:h}"
    return $?
  fi
  if [[ -d "$candidate" ]]; then
    try_set_project_root_from_dir "$candidate"
    return $?
  fi
  log "❌ 路径不存在，或不是目录 / .xcworkspace / .xcodeproj：${candidate}"
  return 1
}

# 从脚本目录逐层向上寻找工程，修复脚本位于 ScriptsByDevTools 时只查一级的问题。
try_set_project_root_from_ancestors() {
  local current="$SCRIPT_DIR"
  local level=0
  while (( level < 8 )); do
    log "自动检查第 $((level + 1)) 层：${current}"
    if try_set_project_root_from_dir "$current"; then
      return 0
    fi
    [[ "$current" == "/" ]] && break
    current="${current:h}"
    (( level += 1 ))
  done
  return 1
}

# 自动定位失败时循环接收人工路径，直到确认有效工程。
prompt_for_project_root() {
  local raw=""
  while true; do
    print
    print -r -- "请输入或拖入：工程根目录、.xcworkspace 或 .xcodeproj。"
    read -r "?$(jobs_prompt_render "路径：")" raw
    raw="$(normalize_user_path "$raw")"
    if [[ -z "$raw" ]]; then
      log "未输入路径，请重新输入。"
      continue
    fi
    if try_set_project_root_from_input_path "$raw"; then
      return 0
    fi
    log "未能确认有效工程，请重新输入。"
  done
}

# 优先使用命令行参数，其次逐层向上扫描，最后进入人工选择。
locate_project_root_or_exit() {
  local supplied_path="${1:-}"
  line
  log "开始定位 Xcode/iOS 工程根目录。"
  if [[ -n "$supplied_path" ]]; then
    supplied_path="$(normalize_user_path "$supplied_path")"
    if try_set_project_root_from_input_path "$supplied_path"; then
      return 0
    fi
    log "命令行参数未通过确认，继续自动扫描。"
  fi
  if try_set_project_root_from_ancestors; then
    return 0
  fi
  prompt_for_project_root || exit 1
}

# 验证 Codex CLI 是否可调用，缺失时只提示官方入口，不代替用户安装。
ensure_codex_cli_or_exit() {
  line
  log "开始 Codex CLI 健康体检。"
  if ! command -v codex >/dev/null 2>&1; then
    log "❌ 未找到 codex 命令。请先从 OpenAI 官方渠道安装 Codex CLI。"
    log "官方说明：https://developers.openai.com/codex/cli"
    finish_and_wait 1
  fi
  log "✅ Codex 路径：$(command -v codex)"
  local version="$(codex --version 2>/dev/null | head -n 1 || true)"
  [[ -n "$version" ]] && log "Codex 版本：${version}"
}

# 对安装和升级动作统一采用“回车跳过、输入任意字符执行”的保守交互。
ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?$(jobs_prompt_render "${message}（直接回车跳过；输入任意字符后回车执行）：")" answer
  [[ -n "$answer" ]]
}

# 下载到独立临时目录并记录哈希，避免直接执行 curl 管道导致内容不可审计。
install_understand_anything_for_codex() {
  local temp_dir=""
  local installer=""
  line
  if ! ask_any_to_run "未检测到 Understand Anything，是否从官方仓库安装"; then
    log "已跳过安装；不会启动 Codex 或生成图谱。"
    finish_and_wait 0
  fi
  command -v curl >/dev/null 2>&1 || { log "❌ 未找到 curl。"; finish_and_wait 1; }
  temp_dir="$(mktemp -d "${TMPDIR%/}/understand-anything.XXXXXX")" || { log "❌ 无法创建临时目录。"; finish_and_wait 1; }
  installer="${temp_dir}/install.sh"
  log "下载安装脚本：${UA_INSTALL_URL}"
  if ! curl --proto '=https' --tlsv1.2 -fsSL "$UA_INSTALL_URL" -o "$installer"; then
    rmdir "$temp_dir" 2>/dev/null || true
    log "❌ 安装脚本下载失败。"
    finish_and_wait 1
  fi
  log "安装脚本 SHA-256：$(shasum -a 256 "$installer" | awk '{print $1}')"
  /bin/bash "$installer" codex
  local code=$?
  rm -f -- "$installer"
  rmdir "$temp_dir" 2>/dev/null || true
  if (( code != 0 )); then
    log "❌ Understand Anything 安装失败，退出码：${code}"
    finish_and_wait "$code"
  fi
}

# 展示当前提交并由用户决定是否调用仓库自带升级入口。
upgrade_understand_anything_if_requested() {
  local branch=""
  local commit=""
  branch="$(git -C "$UA_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  commit="$(git -C "$UA_REPO" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] && log "Understand Anything 分支：${branch}"
  [[ -n "$commit" ]] && log "Understand Anything 提交：${commit}"
  if ! ask_any_to_run "Understand Anything 已安装，是否执行官方升级"; then
    log "已跳过 Understand Anything 升级。"
    return 0
  fi
  if [[ ! -f "$UA_REPO/install.sh" ]]; then
    log "❌ 安装目录缺少 install.sh，停止自动修复，请先检查目录来源。"
    finish_and_wait 1
  fi
  (
    cd "$UA_REPO" || exit 1
    /bin/bash ./install.sh --update
  )
  local code=$?
  if (( code != 0 )); then
    log "❌ Understand Anything 升级失败，退出码：${code}"
    finish_and_wait "$code"
  fi
  log "✅ Understand Anything 升级完成。"
}

# 检查仓库和用户级 Skill 链接，确保安装结果可被新的 Codex 会话加载。
validate_understand_anything_installation_or_exit() {
  if [[ ! -d "$UA_REPO" || ! -f "$UA_REPO/install.sh" ]]; then
    log "❌ 未检测到完整安装目录：${UA_REPO}"
    finish_and_wait 1
  fi
  log "✅ Understand Anything 仓库：${UA_REPO}"
  local skill_count=0
  local skill_path=""
  while IFS= read -r skill_path; do
    [[ -n "$skill_path" ]] || continue
    print -r -- "  - ${skill_path} -> $(readlink "$skill_path" 2>/dev/null || print -r -- '非符号链接')"
    (( skill_count += 1 ))
  done < <(find "$HOME/.agents/skills" -maxdepth 1 -name 'understand*' -print 2>/dev/null | sort)
  if (( skill_count == 0 )); then
    log "⚠️ 未在用户级 Skills 目录发现 understand* 项；重启 Codex 后若命令不可见，请重新执行安装。"
  else
    log "✅ 检测到 ${skill_count} 个 Understand Anything Skill 入口。"
  fi
}

# 按“已安装则可选升级、未安装则可选安装”的顺序完成健康体检。
ensure_understand_anything_or_exit() {
  line
  log "开始 Understand Anything 健康体检。"
  if [[ -d "$UA_REPO" && -f "$UA_REPO/install.sh" ]]; then
    upgrade_understand_anything_if_requested
  else
    install_understand_anything_for_codex
  fi
  validate_understand_anything_installation_or_exit
}

# 输出当前官方命令地图，明确生成图谱仍需用户进入 Codex 后主动执行。
print_understand_anything_usage() {
  line
  log "工程根目录：${PROJECT_ROOT}"
  print -r -- ""
  print -r -- "重新启动 Codex 后，在工程根目录按需要执行："
  print -r -- "  /understand --language zh      # 生成或增量更新代码知识图谱"
  print -r -- "  /understand-dashboard          # 打开交互式图谱"
  print -r -- "  /understand-chat               # 基于图谱提问"
  print -r -- "  /understand-diff               # 分析 Git 变更影响"
  print -r -- "  /understand-explain            # 深入解释文件、函数或模块"
  print -r -- "  /understand-onboard            # 生成项目入门指南"
  print -r -- "  /understand-domain             # 提取业务领域关系"
  print -r -- ""
  print -r -- "图谱通常位于：${PROJECT_ROOT}/.understand-anything/knowledge-graph.json"
  print -r -- "大型项目可先限定自有源码目录；默认增量分析，不要挂接高频构建或 pod install。"
  line
}

# 仅在用户主动输入内容时启动 Codex，直接回车保持无副作用结束。
offer_to_launch_codex() {
  if ! ask_any_to_run "是否现在进入工程根目录并启动 Codex"; then
    log "已选择不启动 Codex。"
    return 0
  fi
  log "进入工程根目录并启动 Codex：${PROJECT_ROOT}"
  cd "$PROJECT_ROOT" || { log "❌ 无法进入工程根目录。"; return 1; }
  codex
}

# 汇总使用说明并把启动动作留给用户最终确认。
show_usage_and_offer_launch() {
  print_understand_anything_usage
  if ! offer_to_launch_codex; then
    log "❌ Codex 启动流程失败。"
    finish_and_wait 1
  fi
}

# 统一输出退出码和日志路径，交互终端中等待用户确认后关闭窗口。
finish_and_wait() {
  local code="${1:-0}"
  print
  log "脚本流程结束，退出码：${code}"
  log "完整日志：${LOG_FILE}"
  read -r "?$(jobs_prompt_render "按回车退出：")" _
  exit "$code"
}

# 主入口只编排高层业务动作，具体控制和异常收口由各函数负责。
# 入口失败在阶段内终止；source 业务继续使用可返回的预检函数。
jobs_ios_python_prepare_runtime() {
  jobs_ios_python_preflight confirmed || exit 1
}


# 按已声明入口顺序编排当前脚本的高层职责。
main() {
  show_script_intro_and_wait "$@" # 先完成无副作用的三层自述确认
  jobs_ios_python_prepare_runtime # 业务确认后使用内嵌函数准备 Homebrew Python。
  initialize_script_runtime # 用户确认后初始化严格选项与日志
  print_runtime_header # 展示脚本身份、路径和日志位置
  locate_project_root_or_exit "$@" # 定位并确认 Xcode/iOS 工程根目录
  ensure_codex_cli_or_exit # 验证 Codex CLI 可用性
  ensure_understand_anything_or_exit # 可选安装或升级并验证 Skill 入口
  show_usage_and_offer_launch # 说明命令并由用户决定是否启动 Codex
  finish_and_wait 0 # 汇总日志并安全退出
}

main "$@"
