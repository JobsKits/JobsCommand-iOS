#!/bin/zsh
# shell: zsh
# Jobs Pod 二进制打包器生成器：在本机把随包 Swift 源码编译成原生 macOS GUI App。
# 运行前先展示完整说明并等待回车；确认后仅写入本脚本同级 Build 目录。

typeset -gr SCRIPT_PATH="${0:A}"
typeset -gr SCRIPT_DIR="${SCRIPT_PATH:h}"
typeset -gr SCRIPT_BASENAME="${SCRIPT_PATH:t}"
typeset -gr SOURCE_DIR="${SCRIPT_DIR}/JobsPodBinaryBuilder/Sources"
typeset -gr BUILD_DIR="${SCRIPT_DIR}/Build"
typeset -gr APP_BUNDLE="${BUILD_DIR}/JobsPodBinaryBuilder.app"
typeset -gr LOG_FILE="${BUILD_DIR}/生成JobsPodBinaryBuilder.log"
typeset -g STAGING_DIR=""

# 打印固定自述，并在产生任何文件前等待用户确认。
show_intro_and_confirm() {
  /usr/bin/clear
  print -r -- "============================================================"
  print -r -- "Jobs Pod 二进制打包器（原生 macOS GUI）"
  print -r -- "============================================================"
  print -r -- ""
  print -r -- "本脚本会做什么："
  print -r -- "1. 使用本机 Xcode Swift 编译器编译随包 SwiftUI/AppKit 源码。"
  print -r -- "2. 在同级 Build 目录生成 JobsPodBinaryBuilder.app。"
  print -r -- "3. 进行临时代码签名，并自动启动 GUI 软件。"
  print -r -- ""
  print -r -- "GUI 软件的工作原则："
  print -r -- "• 扫描整个 JobsByPods，但只打包用户选择主 Pod 的依赖闭包。"
  print -r -- "• 已导入的本地 Pod 是最高权威来源，并自动绑定唯一 :path。"
  print -r -- "• 本地重复 Pod 名直接阻断；本地缺失依赖必须人工判断来源。"
  print -r -- "• 远程 Pod 必须展示元数据并由用户按 Enter 确认。"
  print -r -- "• 双 SDK 预编译通过后，展示最终来源表；再次按 Enter 才正式打包。"
  print -r -- "• 正式阶段实时显示进度和日志，最终验证二进制消费 Demo。"
  print -r -- ""
  print -r -- "环境要求：macOS、完整 Xcode、CocoaPods（pod 命令）。"
  print -r -- "写入范围：${BUILD_DIR}"
  print -r -- "重复运行会替换该目录中的 JobsPodBinaryBuilder.app。"
  print -r -- ""
  print -n -r -- "按 Enter 确认并生成；按 Control+C 取消："
  IFS= read -r
}

# 初始化严格模式、终止信号和构建日志。
init_runtime() {
  setopt ERR_EXIT NO_UNSET PIPE_FAIL NO_NOMATCH
  trap handle_interrupt INT TERM
  /bin/mkdir -p "${BUILD_DIR}"
  : > "${LOG_FILE}"
  log_line "生成器：${SCRIPT_BASENAME}"
  log_line "源码目录：${SOURCE_DIR}"
}

# 检查 Xcode 命令行工具以及随包 Swift 源码。
check_environment() {
  [[ -x "/usr/bin/xcrun" ]] || die "没有找到 /usr/bin/xcrun，请安装完整 Xcode。"
  [[ -x "/usr/bin/codesign" ]] || die "没有找到 /usr/bin/codesign。"
  /usr/bin/xcrun --find swiftc >/dev/null 2>&1 || die "Xcode 中没有可用的 swiftc。"
  local source_files=("${SOURCE_DIR}"/*.swift)
  [[ -e "${source_files[1]}" ]] || die "没有找到 Swift 源码：${SOURCE_DIR}"
  log_line "Swift 编译器：$(/usr/bin/xcrun --find swiftc)"
}

# 创建一次性暂存目录和标准 macOS App Bundle 结构。
prepare_app_bundle() {
  STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsPodBinaryBuilder.XXXXXX")"
  /bin/mkdir -p "${STAGING_DIR}/JobsPodBinaryBuilder.app/Contents/MacOS"
  /bin/mkdir -p "${STAGING_DIR}/JobsPodBinaryBuilder.app/Contents/Resources"
  write_info_plist
  log_line "暂存目录：${STAGING_DIR}"
}

# 使用 plutil 生成 App 的 Info.plist，避免依赖额外模板工具。
write_info_plist() {
  local plist_path="${STAGING_DIR}/JobsPodBinaryBuilder.app/Contents/Info.plist"
  /usr/bin/plutil -create xml1 "${plist_path}"
  /usr/bin/plutil -insert CFBundleDevelopmentRegion -string "zh_CN" "${plist_path}"
  /usr/bin/plutil -insert CFBundleExecutable -string "JobsPodBinaryBuilder" "${plist_path}"
  /usr/bin/plutil -insert CFBundleIdentifier -string "com.jobs.podbinarybuilder" "${plist_path}"
  /usr/bin/plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "${plist_path}"
  /usr/bin/plutil -insert CFBundleName -string "JobsPodBinaryBuilder" "${plist_path}"
  /usr/bin/plutil -insert CFBundleDisplayName -string "Jobs Pod 二进制打包器" "${plist_path}"
  /usr/bin/plutil -insert CFBundlePackageType -string "APPL" "${plist_path}"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "1.0.0" "${plist_path}"
  /usr/bin/plutil -insert CFBundleVersion -string "1" "${plist_path}"
  /usr/bin/plutil -insert LSMinimumSystemVersion -string "14.0" "${plist_path}"
  /usr/bin/plutil -insert NSHighResolutionCapable -bool YES "${plist_path}"
}

# 编译 SwiftUI/AppKit 源码为原生 macOS 可执行文件。
compile_native_app() {
  local output_binary="${STAGING_DIR}/JobsPodBinaryBuilder.app/Contents/MacOS/JobsPodBinaryBuilder"
  local source_files=("${SOURCE_DIR}"/*.swift)
  log_line "开始编译原生 macOS App…"
  if ! /usr/bin/xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework CryptoKit \
    "${source_files[@]}" \
    -o "${output_binary}" 2>&1 | /usr/bin/tee -a "${LOG_FILE}"; then
    die "Swift 编译失败，详情见：${LOG_FILE}"
  fi
  [[ -x "${output_binary}" ]] || die "编译结束但没有生成可执行文件。"
}

# 临时签名 App，并验证 Bundle 的签名结构。
sign_and_verify_app() {
  local staging_app="${STAGING_DIR}/JobsPodBinaryBuilder.app"
  log_line "正在进行本机临时代码签名…"
  /usr/bin/codesign --force --deep --sign - "${staging_app}" >>"${LOG_FILE}" 2>&1
  /usr/bin/codesign --verify --deep --strict "${staging_app}" >>"${LOG_FILE}" 2>&1
}

# 用已验证的暂存 App 替换同级 Build 中的旧生成物。
install_generated_app() {
  local staging_app="${STAGING_DIR}/JobsPodBinaryBuilder.app"
  [[ "${APP_BUNDLE}" == "${BUILD_DIR}/JobsPodBinaryBuilder.app" ]] ||
    die "目标 App 路径校验失败，拒绝替换。"
  if [[ -e "${APP_BUNDLE}" ]]; then
    /bin/rm -rf "${APP_BUNDLE}"
  fi
  /bin/mv "${staging_app}" "${APP_BUNDLE}"
  log_line "已生成：${APP_BUNDLE}"
}

# 启动生成后的 GUI App。
launch_generated_app() {
  print -r -- ""
  print -r -- "✅ 原生 GUI 已生成："
  print -r -- "${APP_BUNDLE}"
  print -r -- ""
  print -r -- "生成日志：${LOG_FILE}"
  print -r -- "正在启动软件…"
  /usr/bin/open "${APP_BUNDLE}"
}

# 把一行状态同时写入终端和生成日志。
log_line() {
  local message="$1"
  print -r -- "${message}"
  print -r -- "${message}" >>"${LOG_FILE}"
}

# 清理本次编译使用的受控暂存目录。
cleanup_staging() {
  if [[ -n "${STAGING_DIR}" &&
        "${STAGING_DIR}" == "${TMPDIR:-/tmp}"/JobsPodBinaryBuilder.* &&
        -d "${STAGING_DIR}" ]]; then
    /bin/rm -rf "${STAGING_DIR}"
  fi
  STAGING_DIR=""
}

# 处理中断信号，清理暂存内容并退出。
handle_interrupt() {
  print -r -- ""
  print -r -- "已取消，没有继续生成。"
  cleanup_staging
  exit 130
}

# 输出错误、清理暂存目录并以失败状态退出。
die() {
  local message="$1"
  print -r -- "❌ ${message}" >&2
  if [[ -d "${BUILD_DIR}" ]]; then
    print -r -- "❌ ${message}" >>"${LOG_FILE}"
  fi
  cleanup_staging
  exit 1
}

# 编排生成器的固定执行顺序。
main() {
  show_intro_and_confirm # 先告知全部行为并等待用户回车授权
  init_runtime # 回车后才初始化 Build 目录与日志
  check_environment # 校验 Xcode、swiftc 和随包源码
  prepare_app_bundle # 创建受控暂存 App Bundle
  compile_native_app # 编译 SwiftUI/AppKit 原生程序
  sign_and_verify_app # 临时签名并验证 App Bundle
  install_generated_app # 安装已验证的生成物
  cleanup_staging # 清理本次暂存目录
  launch_generated_app # 启动 GUI 软件
}

main "$@"
