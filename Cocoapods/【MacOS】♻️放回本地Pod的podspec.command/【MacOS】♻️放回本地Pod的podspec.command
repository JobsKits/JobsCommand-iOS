#!/bin/zsh

set -u

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
    printf "${BLUE}============================================================${NC}\n"
    printf "${BLUE} 放回本地 Pod 的 CocoaPods 相关文件${NC}\n"
    printf "${BLUE}============================================================${NC}\n"
    printf "\n"
    printf "功能说明：\n"
    printf "1. 第一步拖入管理本地 Pod 的文件夹。脚本会在该目录下最多向下一层查找 .podspec。\n"
    printf "2. 第二步拖入装有 .podspec 的文件夹。脚本会读取该目录直接包含的 .podspec，以及一级子文件夹里的 .podspec。\n"
    printf "3. 脚本会按 .podspec 文件名精确匹配，把来源 .podspec 放回本地 Pod 目录中已有的同名 .podspec。\n"
    printf "4. 如果来源 .podspec 同目录存在 JobsPodspecKit.rb，会同步放回到目标 .podspec 同目录：目标已有则覆盖，目标没有则创建。\n"
    printf "5. 不会创建新的 .podspec、Podfile、Podfile.deps、Podfile.lock；这些文件只替换已经存在的同名目标文件。\n"
    printf "6. Podfile、Podfile.deps、Podfile.lock 会逐个询问：直接回车跳过，输入任意字符后回车才替换。\n"
    printf "7. Podfile 三件套默认从本地 Pod 管理目录的上层目录寻找；默认位置不存在时，会要求你拖入目标文件或包含目标文件的文件夹。\n"
    printf "8. 支持拖入路径中的空格、引号、反斜杠转义、~，并会尽量解析 Finder 替身和 Unix 软链接。\n"
    printf "\n"
    printf "${YELLOW}按回车开始执行...${NC}"
    read -r USER_CONFIRM
    printf "\n"
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
        echo "请把管理本地 Pod 的文件夹拖到这里，然后按回车："
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
        echo "请把装有 .podspec 的文件夹拖到这里，然后按回车："
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

    printf "${YELLOW}是否替换 %s？直接回车 = 跳过，输入任意字符后回车 = 替换：${NC}" "$FILE_NAME"
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
        echo "请拖入目标 $PODFILE_NAME 文件，或者拖入包含 $PODFILE_NAME 的文件夹，然后按回车：" >&2
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

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
run_main_flow() {
    trap cleanup_temp_files EXIT

    print_intro
    read_local_pods_dir
    read_podspec_source_dir

    create_temp_files
    build_target_podspec_index
    build_source_podspec_index
    print_index_summary

    restore_podspec_files
    restore_podfiles
    print_result
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
