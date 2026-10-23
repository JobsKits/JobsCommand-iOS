#!/bin/zsh
# 脚本自述：
# - 脚本名称：JobsCodeSnippets 隔离回归。
# - 核心用途：在临时 HOME、本地 bare remote 与独立安装目录验证安装、升级和失败保护。
# - 影响范围：仅创建系统临时目录中的测试仓库、提交和日志，不操作真实 HOME 或远端服务。
# - 运行提示：先阅读内置自述，按回车运行；Ctrl+C 或输入结束取消，测试现场保留供核对。
# shell: zsh

TEST_DIR=""
CORE_SCRIPT=""
TEST_ROOT=""
CORE_LIBRARY=""
CORE_DRIVER=""
CASE_ROOT=""
CASE_HOME=""
CASE_TMP=""
REMOTE=""
PUBLISHER=""
TARGET=""
ASSERT_LOG=""
PASSED=0
FAILED=0
CORE_RC=0
CASE_ID=""

# 展示测试影响范围，确认后才创建夹具。
show_script_intro_and_wait() {
  print -r -- '================ JobsCodeSnippets 隔离回归 ================'
  print -r -- '1、用临时 HOME 和本地 Git 仓库验证安装、升级、暂存状态及失败保护。'
  print -r -- '2、只在测试夹具创建提交；不联网，不操作真实 CodeSnippets 或源仓提交。'
  print -r -- '3、测试日志与现场保留在系统临时目录，结束时显示路径。'
  print -r -- '取消：Ctrl+C；输入结束也会停止。'
  read -r '?已了解用途与影响，按回车运行：' || exit 1
}

# 校验测试入口，避免误把参数当作筛选条件。
validate_test_arguments() {
  [[ $# == 0 ]] || { print -u2 -r -- '✖ 本回归脚本不接受参数。'; exit 2; }
}

# 生成私有测试根及移除末行 main 的核心副本。
prepare_tests() {
  setopt NO_NOMATCH PIPE_FAIL
  TEST_DIR="${${(%):-%x}:A:h}"
  CORE_SCRIPT="$TEST_DIR/../【MacOS】⚙️双击安装JobsCodeSnippets.command"
  [[ -f "$CORE_SCRIPT" ]] || exit 1
  [[ "$(tail -n 1 "$CORE_SCRIPT")" == 'main "$@"' ]] || {
    print -u2 -r -- '✖ 核心末行不是预期入口，拒绝生成 source 副本。'
    exit 1
  }
  TEST_ROOT="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/JobsCodeSnippets-tests.XXXXXXXX")" || exit 1
  CORE_LIBRARY="$TEST_ROOT/core-library.zsh"
  CORE_DRIVER="$TEST_ROOT/core-driver.zsh"
  ASSERT_LOG="$TEST_ROOT/assertions.log"
  sed '$d' "$CORE_SCRIPT" > "$CORE_LIBRARY" || exit 1
  cat > "$CORE_DRIVER" <<'DRIVER'
#!/bin/zsh
source "$CORE_LIBRARY" || exit 1
configure_runtime "$@" || exit 2
ACTION_APPROVED=1
REPO_URLS=("$LOCAL_REMOTE")
if [[ "$TEST_MODE" == finder-probe ]]; then
  ACTION_APPROVED=0
fi
if [[ -n "${RACE_FILE:-}" ]]; then
  functions -c publish_candidate publish_candidate_without_race
  # 在发布前模拟另一个进程修改真实目标。
  publish_candidate() {
    case "$RACE_KIND" in
      chmod) chmod u+x "$CODE_SNIPPETS_PATH/$RACE_FILE" ;;
      symlink) ln -sfn a.codesnippet "$CODE_SNIPPETS_PATH/$RACE_FILE" ;;
      *) print -r -- 'concurrent-write' >> "$CODE_SNIPPETS_PATH/$RACE_FILE" ;;
    esac
    publish_candidate_without_race
  }
fi
check_environment || exit 1
report_state || exit 1
run_business
driver_result=$?
print -r -- "$TRANSACTION_DIR" > "$TEST_CASE_ROOT/transaction-path"
exit "$driver_result"
DRIVER
}

# 每条 Git 命令都隔离用户配置和调用进程的 GIT_* 定位变量。
fixture_git() {
  local repo="$1"
  shift
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$CASE_HOME" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0 \
    GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=file \
    /usr/bin/git -C "$repo" -c user.name='JobsCodeSnippets Test' \
    -c user.email=jobs-snippets-test@example.invalid -c core.hooksPath=/dev/null "$@"
}

# 为每组用例分配独立 HOME、临时目录和仓库路径。
new_case() {
  CASE_ID="$1"
  CASE_ROOT="$TEST_ROOT/$CASE_ID"
  CASE_HOME="$CASE_ROOT/home"
  CASE_TMP="$CASE_ROOT/tmp"
  REMOTE="$CASE_ROOT/remote.git"
  PUBLISHER="$CASE_ROOT/publisher"
  TARGET="$CASE_HOME/Library/Developer/Xcode/UserData/CodeSnippets"
  mkdir -p "$CASE_HOME" "$CASE_TMP"
}

# 用本地裸仓构造发布端和可选的已安装仓库。
make_fixture() {
  local installation="${1:-installed}" line
  fixture_git "$CASE_ROOT" init --bare --initial-branch=main "$REMOTE" >/dev/null
  fixture_git "$CASE_ROOT" init --initial-branch=main "$PUBLISHER" >/dev/null
  for line in {1..24}; do
    printf 'line-%02d\n' "$line"
  done > "$PUBLISHER/a.codesnippet"
  print -r -- $'ignored.cache\nignored-dir/' > "$PUBLISHER/.gitignore"
  print -r -- 'base' > "$PUBLISHER/base.txt"
  fixture_git "$PUBLISHER" add .
  fixture_git "$PUBLISHER" commit -m base >/dev/null
  fixture_git "$PUBLISHER" remote add origin "$REMOTE"
  fixture_git "$PUBLISHER" push -u origin main >/dev/null 2>&1
  if [[ "$installation" == installed ]]; then
    mkdir -p "${TARGET:h}"
    fixture_git "$CASE_ROOT" clone --no-hardlinks "$REMOTE" "$TARGET" >/dev/null 2>&1
  fi
}

# 修改固定行，使本地和远端补丁的重叠关系明确。
replace_line() {
  local file="$1" number="$2" replacement="$3"
  awk -v number="$number" -v replacement="$replacement" \
    'NR == number { print replacement; next } { print }' "$file" > "$CASE_ROOT/rewrite.tmp"
  mv "$CASE_ROOT/rewrite.tmp" "$file"
}

# 只向当前夹具裸仓发布一次可识别的更新。
publish_remote() {
  print -r -- "remote-$CASE_ID" > "$PUBLISHER/remote.txt"
  fixture_git "$PUBLISHER" add .
  fixture_git "$PUBLISHER" commit -m remote-update >/dev/null
  fixture_git "$PUBLISHER" push origin main >/dev/null 2>&1
}

# 在隔离环境中执行实际业务函数或工程门禁探针。
run_core() {
  local mode="${1:-normal}"
  shift
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_OPTIONAL_LOCKS=0 \
    GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 NO_COLOR=1 \
    CORE_LIBRARY="$CORE_LIBRARY" LOCAL_REMOTE="$REMOTE" TEST_MODE="$mode" \
    TEST_CASE_ROOT="$CASE_ROOT" RACE_FILE="${TEST_RACE_FILE:-}" RACE_KIND="${TEST_RACE_KIND:-append}" \
    /bin/zsh -f "$CORE_DRIVER" "$@" > "$CASE_ROOT/core.output" 2>&1
}

# 注入外部仓库定位变量，验证核心会清除调用者污染。
run_core_polluted() {
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file \
    GIT_TERMINAL_PROMPT=0 NO_COLOR=1 CORE_LIBRARY="$CORE_LIBRARY" LOCAL_REMOTE="$REMOTE" \
    TEST_MODE=normal TEST_CASE_ROOT="$CASE_ROOT" \
    GIT_DIR="$CASE_ROOT/outsider/.git" GIT_WORK_TREE="$CASE_ROOT/outsider" \
    GIT_COMMON_DIR="$CASE_ROOT/outsider/.git" GIT_INDEX_FILE="$CASE_ROOT/outsider/.git/index" \
    GIT_OBJECT_DIRECTORY="$CASE_ROOT/outsider/.git/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$CASE_ROOT/outsider/.git/objects" \
    /bin/zsh -f "$CORE_DRIVER" > "$CASE_ROOT/core.output" 2>&1
}

# 通过正式脚本入口验证只读模式的实际副作用。
run_readonly() {
  env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$CASE_HOME" TMPDIR="$CASE_TMP" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ALLOW_PROTOCOL=file NO_COLOR=1 \
    /bin/zsh -f "$CORE_SCRIPT" "$1" > "$CASE_ROOT/core.output" 2>&1
}

# 记录已通过断言，跨用例子进程累计验证数量。
record_assertion() {
  print -r -- "$CASE_ID: $1" >> "$ASSERT_LOG"
}

# 比较业务结果，并在失败时显示预期和实际值。
assert_equal() {
  local actual="$1" expected="$2" message="$3"
  [[ "$actual" == "$expected" ]] || {
    print -u2 -r -- "✖ $message；预期：$expected；实际：$actual"
    return 1
  }
  record_assertion "$message"
}

# 核对关键产物或安全备份存在。
assert_present() {
  [[ -e "$1" ]] || { print -u2 -r -- "✖ 不存在：$1"; return 1; }
  record_assertion "存在：${1:t}"
}

# 核对只读路径、锁或未执行的目标没有遗留产物。
assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || { print -u2 -r -- "✖ 不应存在：$1"; return 1; }
  record_assertion "不存在：${1:t}"
}

# 以字面量核对文件内容和面向用户的失败提示。
assert_contains() {
  grep -Fq -- "$2" "$1" || { print -u2 -r -- "✖ $1 缺少：$2"; return 1; }
  record_assertion "内容存在：$2"
}

# 比较完整目录内容及权限和符号链接信息。
assert_same_tree() {
  diff -qr "$1" "$2" > "$CASE_ROOT/tree.diff" 2>&1 || {
    cat "$CASE_ROOT/tree.diff"
    return 1
  }
  snapshot_metadata "$1" > "$CASE_ROOT/actual.metadata"
  snapshot_metadata "$2" > "$CASE_ROOT/expected.metadata"
  diff -u "$CASE_ROOT/expected.metadata" "$CASE_ROOT/actual.metadata" || return 1
  record_assertion '目录、Git 元数据内容、权限和符号链接相同'
}

# 单独记录 diff 不比较的模式、所有者和链接目标。
snapshot_metadata() {
  (
    cd "$1" || return 1
    local item link_target
    find . -print0 | while IFS= read -r -d '' item; do
      link_target=''
      if [[ -L "$item" ]]; then
        link_target="$(readlink "$item")"
      fi
      printf '%s\t%s\t%s\n' "$item" "$(stat -f '%Sp %u:%g' "$item")" "$link_target"
    done | LC_ALL=C sort
  )
}

# 失败必须非零退出，原目录与索引保留且释放锁。
assert_failed_unchanged() {
  CORE_RC=0
  run_core normal || CORE_RC=$?
  [[ "$CORE_RC" != 0 ]] || { print -u2 -r -- '✖ 预期非零退出，实际成功'; return 1; }
  record_assertion '失败返回非零'
  assert_same_tree "$TARGET" "$CASE_ROOT/before"
  assert_absent "${TARGET:h}/.JobsCodeSnippets.lock"
}

# 缺失安装目录时应克隆到当前临时用户的实际目标。
test_install_missing() {
  new_case install-missing
  make_fixture missing
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$(fixture_git "$REMOTE" rev-parse main)" '首次安装与本地远端一致'
  assert_equal "$(fixture_git "$TARGET" status --porcelain)" '' '首次安装工作区干净'
  assert_present "$TARGET/a.codesnippet"
  assert_absent "${TARGET:h}/.JobsCodeSnippets.lock"
}

# 空安装目录可接管，成功后仍保留原目录备份。
test_install_empty() {
  new_case install-empty
  make_fixture missing
  mkdir -p "$TARGET"
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$(fixture_git "$REMOTE" rev-parse main)" '空目标目录可以安装'
  assert_present "$(cat "$CASE_ROOT/transaction-path")/original"
  assert_present "$(cat "$CASE_ROOT/transaction-path")/previous"
}

# 已是最新的独立仓库保持 HEAD 和干净状态。
test_existing_current() {
  new_case existing-current
  make_fixture
  local start_head="$(fixture_git "$TARGET" rev-parse HEAD)"
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$start_head" '已安装且最新不新增提交'
  assert_equal "$(fixture_git "$TARGET" status --porcelain)" '' '已安装且最新保持干净'
  assert_present "$(cat "$CASE_ROOT/transaction-path")/previous/.git"
}

# 干净仓库升级应快进，且不能向远端写入新提交。
test_clean_fast_forward() {
  new_case clean-fast-forward
  make_fixture
  publish_remote
  local remote_head="$(fixture_git "$REMOTE" rev-parse main)"
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$remote_head" '无本地改动时快进远端'
  assert_equal "$(fixture_git "$TARGET" status --porcelain)" '' '快进后工作区干净'
  assert_equal "$(fixture_git "$REMOTE" rev-parse main)" "$remote_head" '升级不推送或修改远端分支'
  assert_contains "$TARGET/remote.txt" 'remote-clean-fast-forward'
}

# 同一文件的暂存和未暂存补丁应分别保留。
test_partial_stage() {
  new_case partial-stage
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 staged-local
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  replace_line "$PUBLISHER/a.codesnippet" 20 remote-local
  publish_remote
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$(fixture_git "$REMOTE" rev-parse main)" '部分暂存升级没有生成本地提交'
  fixture_git "$TARGET" show :a.codesnippet > "$CASE_ROOT/index-content"
  assert_contains "$CASE_ROOT/index-content" staged-local
  assert_contains "$CASE_ROOT/index-content" line-08
  assert_contains "$CASE_ROOT/index-content" remote-local
  assert_contains "$TARGET/a.codesnippet" staged-local
  assert_contains "$TARGET/a.codesnippet" unstaged-local
  assert_contains "$TARGET/a.codesnippet" remote-local
  assert_equal "$(fixture_git "$TARGET" status --porcelain -- a.codesnippet)" 'MM a.codesnippet' '同一文件保留暂存和未暂存层次'
  assert_equal "$(fixture_git "$TARGET" stash list)" '' '本次安全 stash 成功后清理'
}

# 升级保留未跟踪、忽略、中文与空格路径内容。
test_untracked_ignored() {
  new_case untracked-ignored
  make_fixture
  mkdir -p "$TARGET/ignored-dir/中文 空格"
  print -r -- 'untracked-kept' > "$TARGET/未跟踪 空格.codesnippet"
  print -r -- 'ignored-kept' > "$TARGET/ignored.cache"
  print -r -- 'nested-ignored-kept' > "$TARGET/ignored-dir/中文 空格/value"
  publish_remote
  run_core normal
  assert_contains "$TARGET/未跟踪 空格.codesnippet" untracked-kept
  assert_contains "$TARGET/ignored.cache" ignored-kept
  assert_contains "$TARGET/ignored-dir/中文 空格/value" nested-ignored-kept
  assert_equal "$(fixture_git "$TARGET" ls-files --stage -- '未跟踪 空格.codesnippet')" '' '未跟踪文件仍未进入索引'
}

# 远端新文件不能覆盖本地已有的忽略内容。
test_ignored_collision() {
  new_case ignored-collision
  make_fixture
  print -r -- 'personal-ignored-content' > "$TARGET/ignored.cache"
  print -r -- 'remote-now-tracked' > "$PUBLISHER/ignored.cache"
  fixture_git "$PUBLISHER" add -f ignored.cache
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_contains "$TARGET/ignored.cache" personal-ignored-content
  assert_contains "$CASE_ROOT/core.output" '请手动合并'
}

# 安全暂存不能丢失或重排用户原有 stash。
test_existing_stash() {
  new_case existing-stash
  make_fixture
  replace_line "$TARGET/a.codesnippet" 5 original-stash
  fixture_git "$TARGET" stash push -m pre-existing >/dev/null
  local stash_before="$(fixture_git "$TARGET" stash list --format='%H %s')"
  replace_line "$TARGET/a.codesnippet" 2 staged-local
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  publish_remote
  run_core normal
  assert_equal "$(fixture_git "$TARGET" stash list --format='%H %s')" "$stash_before" '已有 stash 对象与顺序保持不变'
  assert_contains "$TARGET/a.codesnippet" staged-local
  assert_contains "$TARGET/a.codesnippet" unstaged-local
  assert_equal "$(fixture_git "$TARGET" status --porcelain -- a.codesnippet)" 'MM a.codesnippet' '已有 stash 时也保留部分暂存'
}

# 远端失效时完整保留原目录和部分暂存状态。
test_fetch_failure() {
  new_case fetch-failure
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 staged-local
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  print -r -- 'untracked' > "$TARGET/untracked.codesnippet"
  fixture_git "$TARGET" remote set-url origin "$CASE_ROOT/does-not-exist.git"
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '请手动合并'
  assert_present "$(cat "$CASE_ROOT/transaction-path")/candidate/.git/refs/stash"
}

# 恢复本地补丁冲突时保留真实目标和失败候选。
test_restore_conflict() {
  new_case restore-conflict
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 local-conflict
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  replace_line "$PUBLISHER/a.codesnippet" 2 remote-conflict
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '请手动合并'
  assert_present "$(cat "$CASE_ROOT/transaction-path")/candidate/.git/refs/stash"
}

# 可合并分叉应停留在待提交状态，不生成 commit。
test_diverged_clean() {
  new_case diverged-clean
  make_fixture
  print -r -- 'local-commit' > "$TARGET/local.txt"
  fixture_git "$TARGET" add local.txt
  fixture_git "$TARGET" commit -m local-only >/dev/null
  local original_head="$(fixture_git "$TARGET" rev-parse HEAD)"
  publish_remote
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$original_head" '分叉合并不自动生成 commit'
  assert_equal "$(cat "$TARGET/.git/MERGE_HEAD")" "$(fixture_git "$REMOTE" rev-parse main)" '分叉合并保留待提交状态'
  assert_equal "$(fixture_git "$TARGET" status --porcelain -- remote.txt)" 'A  remote.txt' '远端合并内容留在暂存区'
  assert_contains "$TARGET/local.txt" local-commit
  assert_contains "$TARGET/remote.txt" remote-diverged-clean
}

# 分叉合并同时保留远端合并结果和本地部分暂存。
test_diverged_dirty() {
  new_case diverged-dirty
  make_fixture
  print -r -- 'local-commit' > "$TARGET/local.txt"
  fixture_git "$TARGET" add local.txt
  fixture_git "$TARGET" commit -m local-only >/dev/null
  local original_head="$(fixture_git "$TARGET" rev-parse HEAD)"
  replace_line "$TARGET/a.codesnippet" 2 staged-local
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  replace_line "$PUBLISHER/a.codesnippet" 20 remote-local
  publish_remote
  run_core normal
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$original_head" '脏仓分叉合并仍不生成 commit'
  assert_equal "$(cat "$TARGET/.git/MERGE_HEAD")" "$(fixture_git "$REMOTE" rev-parse main)" '脏仓分叉保留远端待提交合并'
  fixture_git "$TARGET" show :a.codesnippet > "$CASE_ROOT/index-content"
  assert_contains "$CASE_ROOT/index-content" staged-local
  assert_contains "$CASE_ROOT/index-content" line-08
  assert_contains "$CASE_ROOT/index-content" remote-local
  assert_contains "$TARGET/a.codesnippet" unstaged-local
  assert_contains "$TARGET/local.txt" local-commit
  assert_equal "$(fixture_git "$TARGET" status --porcelain -- a.codesnippet)" 'MM a.codesnippet' '分叉合并保留原有部分暂存'
  assert_equal "$(fixture_git "$TARGET" status --porcelain -- remote.txt)" 'A  remote.txt' '分叉合并保留远端新增文件暂存'
}

# 已提交历史发生合并冲突时真实目标仍保持原状。
test_diverged_conflict() {
  new_case diverged-conflict
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 committed-local
  fixture_git "$TARGET" add a.codesnippet
  fixture_git "$TARGET" commit -m local-conflict >/dev/null
  replace_line "$PUBLISHER/a.codesnippet" 2 committed-remote
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '请手动合并'
}

# 未配置明确上游时停止升级且保留仓库原状。
test_missing_upstream() {
  new_case missing-upstream
  make_fixture
  fixture_git "$TARGET" config --unset branch.main.merge
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
}

# 已有未完成合并必须在创建业务日志前拒绝。
test_incomplete_merge() {
  new_case incomplete-merge
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 committed-local
  fixture_git "$TARGET" add a.codesnippet
  fixture_git "$TARGET" commit -m local-conflict >/dev/null
  replace_line "$PUBLISHER/a.codesnippet" 2 committed-remote
  publish_remote
  fixture_git "$TARGET" fetch origin >/dev/null 2>&1
  fixture_git "$TARGET" merge --no-commit origin/main >/dev/null 2>&1 || true
  assert_present "$TARGET/.git/MERGE_HEAD"
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_equal "$(find "$CASE_TMP" -type f -print)" '' '未完合并在创建业务日志前拒绝'
}

# 非 Git 的个人片段目录不能被自动接管覆盖。
test_non_git_nonempty() {
  new_case non-git-nonempty
  mkdir -p "$TARGET"
  print -r -- 'personal-snippet' > "$TARGET/personal.codesnippet"
  cp -pR "$TARGET" "$CASE_ROOT/before"
  assert_failed_unchanged
  assert_equal "$(find "$CASE_TMP" -type f -print)" '' '非 Git 非空目录在写日志前拒绝'
}

# 从其它工程启动时只能更新实际 CodeSnippets 仓库。
test_git_environment() {
  new_case git-environment
  make_fixture
  fixture_git "$CASE_ROOT" clone --no-hardlinks "$REMOTE" "$CASE_ROOT/outsider" >/dev/null 2>&1
  cp -pR "$CASE_ROOT/outsider" "$CASE_ROOT/outsider-before"
  publish_remote
  run_core_polluted
  assert_equal "$(fixture_git "$TARGET" rev-parse HEAD)" "$(fixture_git "$REMOTE" rev-parse main)" '外部 GIT_* 变量不改变目标仓库'
  assert_same_tree "$CASE_ROOT/outsider" "$CASE_ROOT/outsider-before"
}

# 传输期间外部写入内容时停止发布并保留该写入。
test_concurrent_change() {
  new_case concurrent-change
  make_fixture
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  print -r -- 'concurrent-write' >> "$CASE_ROOT/before/a.codesnippet"
  local TEST_RACE_FILE=a.codesnippet
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '原目录在操作期间发生变化'
}

# 仅权限发生并发变化也必须停止替换。
test_concurrent_chmod() {
  new_case concurrent-chmod
  make_fixture
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  chmod u+x "$CASE_ROOT/before/a.codesnippet"
  local TEST_RACE_FILE=a.codesnippet TEST_RACE_KIND=chmod
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '原目录在操作期间发生变化'
  assert_equal "$(stat -f '%Lp' "$TARGET/a.codesnippet")" "$(stat -f '%Lp' "$CASE_ROOT/before/a.codesnippet")" '并发权限变更保留在原目标'
}

# 符号链接目标并发变化时保留用户的新链接。
test_concurrent_symlink() {
  new_case concurrent-symlink
  make_fixture
  ln -s base.txt "$TARGET/local-link"
  publish_remote
  cp -pR "$TARGET" "$CASE_ROOT/before"
  ln -sfn a.codesnippet "$CASE_ROOT/before/local-link"
  local TEST_RACE_FILE=local-link TEST_RACE_KIND=symlink
  assert_failed_unchanged
  assert_contains "$CASE_ROOT/core.output" '原目录在操作期间发生变化'
  assert_equal "$(readlink "$TARGET/local-link")" a.codesnippet '并发符号链接变更保留在原目标'
}

# 未安装时真实 --check 入口不创建任何用户文件。
test_check_missing() {
  new_case check-missing
  cp -pR "$CASE_HOME" "$CASE_ROOT/home-before"
  run_readonly --check
  assert_same_tree "$CASE_HOME" "$CASE_ROOT/home-before"
  assert_equal "$(find "$CASE_TMP" -mindepth 1 -print)" '' '--check 不创建日志、锁或事务'
  assert_contains "$CASE_ROOT/core.output" '尚未安装'
}

# 脏仓库只读检查不能刷新索引或创建日志。
test_check_installed() {
  new_case check-installed
  make_fixture
  replace_line "$TARGET/a.codesnippet" 2 staged-local
  fixture_git "$TARGET" add a.codesnippet
  replace_line "$TARGET/a.codesnippet" 8 unstaged-local
  cp -pR "$CASE_HOME" "$CASE_ROOT/home-before"
  run_readonly --check
  assert_same_tree "$CASE_HOME" "$CASE_ROOT/home-before"
  assert_equal "$(find "$CASE_TMP" -mindepth 1 -print)" '' '--check 不落盘日志或刷新真实索引'
  assert_contains "$CASE_ROOT/core.output" '已安装'
}

# 工程资格按当前层原生标记判断，并排除桌面和选中链接。
test_finder_project_gate() {
  new_case finder-project-gate
  local project="$CASE_ROOT/iOS 工程" result
  mkdir -p "$project/App.xcodeproj" "$project/App.xcworkspace" "$CASE_ROOT/plain" \
    "$CASE_ROOT/swift-package" "$CASE_ROOT/flutter/ios/Runner.xcodeproj" \
    "$CASE_ROOT/pod-project" "$CASE_ROOT/podspec-project" "$CASE_ROOT/hidden-podspec" "$CASE_HOME/Desktop"
  print -r -- 'project fixture' > "$project/App.xcodeproj/project.pbxproj"
  print -r -- 'workspace fixture' > "$project/App.xcworkspace/contents.xcworkspacedata"
  print -r -- '// swift-tools-version: 6.0' > "$CASE_ROOT/swift-package/Package.swift"
  print -r -- 'name: flutter_fixture' > "$CASE_ROOT/flutter/pubspec.yaml"
  print -r -- 'project fixture' > "$CASE_ROOT/flutter/ios/Runner.xcodeproj/project.pbxproj"
  print -r -- "platform :ios, '15.0'" > "$CASE_ROOT/pod-project/Podfile"
  print -r -- 'Pod::Spec.new do |s| end' > "$CASE_ROOT/podspec-project/Demo.podspec"
  print -r -- 'Pod::Spec.new do |s| end' > "$CASE_ROOT/hidden-podspec/.Hidden.podspec"
  print -r -- '// swift-tools-version: 6.0' > "$CASE_HOME/Desktop/Package.swift"
  ln -s "$project" "$CASE_ROOT/project-link"
  local item
  for item in "$project" "$project/App.xcodeproj" "$project/App.xcworkspace" \
    "$CASE_ROOT/swift-package" "$CASE_ROOT/flutter/ios" "$CASE_ROOT/pod-project" \
    "$CASE_ROOT/podspec-project" "$CASE_ROOT/hidden-podspec"; do
    run_core finder-probe --finder "$item"
    record_assertion "工程门禁接受：${item:t}"
  done
  for item in "$CASE_ROOT/plain" "$CASE_ROOT/flutter" "$CASE_ROOT/not-found" \
    "$CASE_ROOT/project-link" "$CASE_HOME/Desktop"; do
    result=0
    run_core finder-probe --finder "$item" || result=$?
    [[ "$result" != 0 ]] || { print -u2 -r -- "✖ 工程门禁错误接受：$item"; return 1; }
    record_assertion "工程门禁拒绝：${item:t}"
  done
  assert_absent "$TARGET"
  assert_equal "$(find "$CASE_TMP" -mindepth 1 -print)" '' '门禁探针不执行安装'
}

# 用独立子进程收集单组失败，继续执行其它用例。
run_case() {
  local callback="$1" result
  (
    setopt ERR_EXIT
    "$callback"
  ) > "$TEST_ROOT/$callback.output" 2>&1
  result=$?
  if (( result == 0 )); then
    (( PASSED += 1 ))
    print -r -- "✔ $callback"
  else
    (( FAILED += 1 ))
    print -r -- "✖ $callback（退出 $result）"
    cat "$TEST_ROOT/$callback.output"
  fi
}

# 顺序执行全部隔离用例，统计由各组结果累计。
run_all_cases() {
  local callback
  for callback in test_install_missing test_install_empty test_existing_current \
    test_clean_fast_forward test_partial_stage test_untracked_ignored test_ignored_collision test_existing_stash \
    test_fetch_failure test_restore_conflict test_diverged_clean test_diverged_dirty \
    test_diverged_conflict test_missing_upstream test_incomplete_merge test_non_git_nonempty \
    test_git_environment test_concurrent_change test_concurrent_chmod test_concurrent_symlink \
    test_check_missing test_check_installed \
    test_finder_project_gate; do
    run_case "$callback"
  done
}

# 打印并落盘汇总，失败组数决定最终退出码。
report_results() {
  print -r -- "通过：$PASSED；失败：$FAILED；断言：$(wc -l < "$ASSERT_LOG" | tr -d ' ')" | tee "$TEST_ROOT/summary.txt"
  print -r -- "日志与隔离现场：$TEST_ROOT"
  (( FAILED == 0 ))
}

# 入口只编排测试职责，业务和分支留在各函数。
main() {
  show_script_intro_and_wait # 展示用途和影响，等待回车确认。
  validate_test_arguments "$@" # 拒绝未支持的测试参数。
  prepare_tests # 创建私有夹具根与核心驱动副本。
  run_all_cases # 执行用例并收集各组结果。
  report_results # 输出断言数、现场位置及退出状态。
}

main "$@"
