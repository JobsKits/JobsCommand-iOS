#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】Xcode编译耗时菜单栏.command
# - 核心用途：生成并启动一个 macOS 菜单栏小工具，监听 Xcode DerivedData 构建日志并展示最近编译耗时与悬浮看板。
# - 影响范围：会在 ~/.xcode-build-timer 目录生成 Swift 源码、App Bundle 和运行日志，不修改 Xcode 与项目文件。
# - 运行提示：运行后会先打印内置自述；确认后检查 Xcode/Swift 环境，随后编译并打开菜单栏工具。

setopt NO_NOMATCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
LOG_READY="0"

APP_NAME="XcodeBuildTimer"
WORK_DIR="${HOME}/.xcode-build-timer"
SOURCE_FILE="${WORK_DIR}/${APP_NAME}.swift"
APP_BUNDLE="${WORK_DIR}/${APP_NAME}.app"
APP_CONTENTS="${APP_BUNDLE}/Contents"
APP_MACOS="${APP_CONTENTS}/MacOS"
APP_EXECUTABLE="${APP_MACOS}/${APP_NAME}"
APP_INFO_PLIST="${APP_CONTENTS}/Info.plist"
HOOK_SCRIPT="${WORK_DIR}/xbt-build-hook.sh"

log() {
  if [[ "${LOG_READY}" == "1" ]]; then
    echo -e "$1" | tee -a "$LOG_FILE"
  else
    echo -e "$1"
  fi
}

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

show_script_intro_and_wait() {
  local current_arch=""
  current_arch="$(uname -m)"
  clear
  highlight_echo "============================== 脚本自述 =============================="
  note_echo "当前脚本：${SCRIPT_PATH}"
  note_echo "核心用途：生成并启动 Xcode 编译耗时菜单栏工具。"
  note_echo "主要能力：通过 Xcode Scheme Pre/Post Action 精准识别编译开始/结束，并在菜单栏与悬浮窗动态显示当前耗时。"
  note_echo "兜底能力：未配置 Scheme Hook 时，仍会自动读取 DerivedData 的 .xcactivitylog 展示最近构建记录。"
  note_echo "兼容策略：脚本会按当前 Mac 芯片原生编译，Apple Silicon 编译 arm64，Intel Mac 编译 x86_64。"
  note_echo "兼容边界：公开资料显示 macOS Tahoe 26 是 Intel Mac 最后一个大版本；当前脚本按 macOS 13.0+ 部署目标编译，覆盖 Intel 最后支持线。"
  note_echo "运行策略：确认后会先结束内存里可能已开启的 ${APP_NAME}，清理旧 App Bundle，再重新编译并启动。"
  warn_echo "影响范围：仅写入 ${WORK_DIR} 与 ${LOG_FILE}，不修改 Xcode、不修改工程、不安装系统插件。"
  gray_echo "Hook 脚本：${HOOK_SCRIPT}"
  gray_echo "当前机器架构：${current_arch}"
  gray_echo "取消方式：按 Ctrl+C 终止；确认前不会生成或更新工具。"
  highlight_echo "======================================================================="
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}

init_runtime() {
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"
  LOG_READY="1"
  info_echo "日志文件：${LOG_FILE}"
}

check_environment() {
  local current_arch=""
  current_arch="$(uname -m)"

  case "$current_arch" in
    arm64|x86_64)
      gray_echo "当前芯片架构：${current_arch}"
      ;;
    *)
      warn_echo "当前芯片架构为 ${current_arch}，不是常见的 arm64 / x86_64；脚本会继续尝试原生编译。"
      ;;
  esac

  if ! command -v xcrun >/dev/null 2>&1; then
    error_echo "未找到 xcrun。请先安装 Xcode 或 Command Line Tools。"
    return 1
  fi

  if ! xcrun --find swiftc >/dev/null 2>&1; then
    error_echo "未找到 swiftc。请先打开 Xcode 完成组件安装，或执行 xcode-select 指向完整 Xcode。"
    return 1
  fi

  if [[ ! -d "${HOME}/Library/Developer/Xcode/DerivedData" ]]; then
    warn_echo "未发现 DerivedData 目录：${HOME}/Library/Developer/Xcode/DerivedData"
    warn_echo "工具仍会启动；等 Xcode 产生构建日志后菜单会自动刷新。"
  fi

  success_echo "环境检查通过。"
}

clean_running_environment() {
  info_echo "清理旧运行环境。"

  if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
    warn_echo "发现旧的 ${APP_NAME} 进程，正在结束。"
    pkill -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true

    local wait_count=0
    while pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1 && [[ $wait_count -lt 20 ]]; do
      sleep 0.2
      wait_count=$((wait_count + 1))
    done

    if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
      warn_echo "旧进程未正常退出，尝试强制结束。"
      pkill -9 -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true
      sleep 0.5
    fi
  else
    gray_echo "未发现旧的 ${APP_NAME} 进程。"
  fi

  if [[ -d "$WORK_DIR/state/builds" ]]; then
    find "$WORK_DIR/state/builds" -type f -name "*.env" -delete 2>/dev/null || true
    gray_echo "已清理残留的运行中计时状态。"
  fi

  rm -rf "$APP_BUNDLE"
  mkdir -p "$WORK_DIR" "$APP_CONTENTS" "$APP_MACOS"
  success_echo "旧 App Bundle 已清理并重建目录。"
}

write_hook_script() {
  mkdir -p "$WORK_DIR/state"

  if [[ -f "$HOOK_SCRIPT" ]]; then
    local replace_answer=""
    warn_echo "已存在 Scheme Hook：${HOOK_SCRIPT}"
    read -r "?👉 直接回车跳过替换；输入任意字符后回车替换：" replace_answer
    if [[ -z "$replace_answer" ]]; then
      gray_echo "已跳过替换 Scheme Hook。"
      chmod +x "$HOOK_SCRIPT" >/dev/null 2>&1 || true
      return 0
    fi
  fi

  cat > "$HOOK_SCRIPT" <<'HOOK_SOURCE'
#!/bin/zsh
setopt NO_NOMATCH

STATE_DIR="${HOME}/.xcode-build-timer/state"
BUILDS_DIR="${STATE_DIR}/builds"
CURRENT_FILE="${STATE_DIR}/latest.env"
HISTORY_FILE="${STATE_DIR}/history.log"
ACTION="${1:-}"

mkdir -p "$STATE_DIR" "$BUILDS_DIR"

escape_value() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  print -r -- "$value"
}

now_epoch() {
  date +%s
}

raw_key() {
  local project="${PROJECT_NAME:-UnknownProject}"
  local scheme="${SCHEME_NAME:-UnknownScheme}"
  local config="${CONFIGURATION:-UnknownConfig}"
  local sdk="${SDK_NAME:-}"
  local platform="${PLATFORM_NAME:-${EFFECTIVE_PLATFORM_NAME:-}}"
  local destination_name="${RUN_DESTINATION_DEVICE_NAME:-${TARGET_DEVICE_NAME:-}}"
  local destination_id="${RUN_DESTINATION_DEVICE_IDENTIFIER:-${TARGET_DEVICE_IDENTIFIER:-}}"
  print -r -- "${project}|${scheme}|${config}|${sdk}|${platform}|${destination_name}|${destination_id}"
}

state_file_for_current_context() {
  local checksum=""
  checksum="$(raw_key | cksum | awk '{print $1}')"
  print -r -- "${BUILDS_DIR}/${checksum}.env"
}

write_state() {
  local build_status="$1"
  local start_epoch="$2"
  local end_epoch="$3"
  local duration="$4"
  local project="${PROJECT_NAME:-UnknownProject}"
  local scheme="${SCHEME_NAME:-UnknownScheme}"
  local config="${CONFIGURATION:-UnknownConfig}"
  local target="${TARGET_NAME:-}"
  local sdk="${SDK_NAME:-}"
  local platform="${PLATFORM_NAME:-${EFFECTIVE_PLATFORM_NAME:-}}"
  local destination_name="${RUN_DESTINATION_DEVICE_NAME:-${TARGET_DEVICE_NAME:-}}"
  local destination_id="${RUN_DESTINATION_DEVICE_IDENTIFIER:-${TARGET_DEVICE_IDENTIFIER:-}}"
  local state_file=""
  state_file="$(state_file_for_current_context)"

  {
    print -r -- "status=\"$(escape_value "$build_status")\""
    print -r -- "start_epoch=\"$(escape_value "$start_epoch")\""
    print -r -- "end_epoch=\"$(escape_value "$end_epoch")\""
    print -r -- "duration=\"$(escape_value "$duration")\""
    print -r -- "project=\"$(escape_value "$project")\""
    print -r -- "scheme=\"$(escape_value "$scheme")\""
    print -r -- "config=\"$(escape_value "$config")\""
    print -r -- "target=\"$(escape_value "$target")\""
    print -r -- "sdk=\"$(escape_value "$sdk")\""
    print -r -- "platform=\"$(escape_value "$platform")\""
    print -r -- "destination_name=\"$(escape_value "$destination_name")\""
    print -r -- "destination_id=\"$(escape_value "$destination_id")\""
    print -r -- "key=\"$(escape_value "$(raw_key)")\""
    print -r -- "updated_at=\"$(now_epoch)\""
  } > "$state_file"
  cp "$state_file" "$CURRENT_FILE"
}

read_value() {
  local key="$1"
  local state_file=""
  state_file="$(state_file_for_current_context)"
  [[ -f "$state_file" ]] || return 0
  awk -F= -v key="$key" '$1 == key {gsub(/^"/, "", $2); gsub(/"$/, "", $2); print $2; exit}' "$state_file"
}

case "$ACTION" in
  start)
    start_epoch="$(now_epoch)"
    write_state "running" "$start_epoch" "" ""
    printf '[%s] start project=%s scheme=%s config=%s target=%s sdk=%s platform=%s destination=%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" \
      "${PROJECT_NAME:-UnknownProject}" \
      "${SCHEME_NAME:-UnknownScheme}" \
      "${CONFIGURATION:-UnknownConfig}" \
      "${TARGET_NAME:-}" \
      "${SDK_NAME:-}" \
      "${PLATFORM_NAME:-${EFFECTIVE_PLATFORM_NAME:-}}" \
      "${RUN_DESTINATION_DEVICE_NAME:-${TARGET_DEVICE_NAME:-}}" >> "$HISTORY_FILE"
    ;;
  end)
    end_epoch="$(now_epoch)"
    start_epoch="$(read_value start_epoch)"
    [[ -n "$start_epoch" ]] || start_epoch="$end_epoch"
    duration=$((end_epoch - start_epoch))
    write_state "finished" "$start_epoch" "$end_epoch" "$duration"
    printf '[%s] end project=%s scheme=%s config=%s sdk=%s destination=%s duration=%s\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" \
      "${PROJECT_NAME:-UnknownProject}" \
      "${SCHEME_NAME:-UnknownScheme}" \
      "${CONFIGURATION:-UnknownConfig}" \
      "${SDK_NAME:-}" \
      "${RUN_DESTINATION_DEVICE_NAME:-${TARGET_DEVICE_NAME:-}}" \
      "$duration" >> "$HISTORY_FILE"
    ;;
  *)
    echo "Usage: $0 start|end" >&2
    exit 2
    ;;
esac
HOOK_SOURCE

  chmod +x "$HOOK_SCRIPT"
  success_echo "已写入 Scheme Hook：${HOOK_SCRIPT}"
}

write_swift_source() {
  mkdir -p "$WORK_DIR"
  cat > "$SOURCE_FILE" <<'SWIFT_SOURCE'
import Cocoa
import Foundation

struct BuildRecord {
    let project: String
    let logPath: String
    let modifiedAt: Date
    let duration: TimeInterval?
    let status: String
    let slowSwift: [String]
    let slowScripts: [String]
    let slowTargets: [String]
}

struct BuildHookState {
    let status: String
    let startEpoch: TimeInterval?
    let endEpoch: TimeInterval?
    let duration: TimeInterval?
    let project: String
    let scheme: String
    let config: String
    let target: String
    let sdk: String
    let platform: String
    let destinationName: String
    let destinationID: String
    let key: String
    let updatedAt: TimeInterval?
    let filePath: String
    let finishReason: String

    var isRunning: Bool {
        status == "running"
    }

    var elapsed: TimeInterval? {
        if isRunning, let startEpoch {
            return max(Date().timeIntervalSince1970 - startEpoch, 0)
        }
        return duration
    }
}

final class BuildStateReader {
    private let buildsDir = NSString(string: "~/.xcode-build-timer/state/builds").expandingTildeInPath
    private let currentFile = NSString(string: "~/.xcode-build-timer/state/latest.env").expandingTildeInPath
    private let fileManager = FileManager.default

    func currentStates() -> [BuildHookState] {
        let root = URL(fileURLWithPath: buildsDir)
        guard let files = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "env" }
            .compactMap { state(from: $0) }
            .filter { state in
                guard let updatedAt = state.updatedAt else {
                    return true
                }
                return Date().timeIntervalSince1970 - updatedAt < 86_400
            }
            .sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
            }
    }

    private func state(from url: URL) -> BuildHookState? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        var values: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            guard let equalIndex = line.firstIndex(of: "=") else {
                continue
            }
            let key = String(line[..<equalIndex])
            var value = String(line[line.index(after: equalIndex)...])
            if value.hasPrefix("\"") {
                value.removeFirst()
            }
            if value.hasSuffix("\"") {
                value.removeLast()
            }
            values[key] = value
        }

        guard let status = values["status"], !status.isEmpty else {
            return nil
        }

        return BuildHookState(
            status: status,
            startEpoch: Double(values["start_epoch"] ?? ""),
            endEpoch: Double(values["end_epoch"] ?? ""),
            duration: Double(values["duration"] ?? ""),
            project: values["project"] ?? "UnknownProject",
            scheme: values["scheme"] ?? "UnknownScheme",
            config: values["config"] ?? "UnknownConfig",
            target: values["target"] ?? "",
            sdk: values["sdk"] ?? "",
            platform: values["platform"] ?? "",
            destinationName: values["destination_name"] ?? "",
            destinationID: values["destination_id"] ?? "",
            key: values["key"] ?? url.deletingPathExtension().lastPathComponent,
            updatedAt: Double(values["updated_at"] ?? ""),
            filePath: url.path,
            finishReason: values["finish_reason"] ?? ""
        )
    }

    func finishRunningState(_ state: BuildHookState, reason: String) {
        guard state.isRunning, state.startEpoch != nil else {
            return
        }

        finishRunningState(state, reason: reason, endEpoch: Date().timeIntervalSince1970)
    }

    func finishRunningState(_ state: BuildHookState, reason: String, endEpoch preferredEndEpoch: TimeInterval) {
        guard state.isRunning, let startEpoch = state.startEpoch else {
            return
        }

        let endEpoch = max(preferredEndEpoch, startEpoch)
        let duration = max(Int(endEpoch - startEpoch), 0)
        let stateURL = URL(fileURLWithPath: state.filePath)
        let content = """
status="finished"
start_epoch="\(escape(state.startEpoch.map { String(Int($0)) } ?? ""))"
end_epoch="\(escape(String(Int(endEpoch))))"
duration="\(escape(String(duration)))"
project="\(escape(state.project))"
scheme="\(escape(state.scheme))"
config="\(escape(state.config))"
target="\(escape(state.target))"
sdk="\(escape(state.sdk))"
platform="\(escape(state.platform))"
destination_name="\(escape(state.destinationName))"
destination_id="\(escape(state.destinationID))"
key="\(escape(state.key))"
updated_at="\(escape(String(Int(endEpoch))))"
finish_reason="\(escape(reason))"
"""
        try? content.write(to: stateURL, atomically: true, encoding: .utf8)
        appendHistory(state: state, duration: duration, reason: reason)
    }

    func discardState(_ state: BuildHookState, reason: String) {
        try? fileManager.removeItem(atPath: state.filePath)
        appendHistory(state: state, duration: 0, reason: reason)
    }

    func reviveAutoFinishedState(_ state: BuildHookState) {
        guard !state.isRunning,
              state.finishReason == "no-build-process-after-failure-or-cancel",
              let startEpoch = state.startEpoch else {
            return
        }

        let now = Date().timeIntervalSince1970
        let stateURL = URL(fileURLWithPath: state.filePath)
        let content = """
status="running"
start_epoch="\(escape(String(Int(startEpoch))))"
end_epoch=""
duration=""
project="\(escape(state.project))"
scheme="\(escape(state.scheme))"
config="\(escape(state.config))"
target="\(escape(state.target))"
sdk="\(escape(state.sdk))"
platform="\(escape(state.platform))"
destination_name="\(escape(state.destinationName))"
destination_id="\(escape(state.destinationID))"
key="\(escape(state.key))"
updated_at="\(escape(String(Int(now))))"
"""
        try? content.write(to: stateURL, atomically: true, encoding: .utf8)
    }

    func clearTimingStates() {
        let root = URL(fileURLWithPath: buildsDir, isDirectory: true)
        if let files = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for file in files where file.pathExtension == "env" {
                try? fileManager.removeItem(at: file)
            }
        }
        try? fileManager.removeItem(atPath: currentFile)
    }

    private func appendHistory(state: BuildHookState, duration: Int, reason: String) {
        let historyPath = NSString(string: "~/.xcode-build-timer/state/history.log").expandingTildeInPath
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] auto-end project=\(state.project) scheme=\(state.scheme) config=\(state.config) sdk=\(state.sdk) destination=\(state.destinationName) duration=\(duration) reason=\(reason)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        if fileManager.fileExists(atPath: historyPath), let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: historyPath)) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: historyPath))
        }
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

struct InferredBuildActivity {
    let isActive: Bool
    let summary: String
}

final class StatusDotView: NSView {
    private var blinkTimer: Timer?
    private var pulseOn = true

    var isRunning = false {
        didSet {
            syncBlinkTimer()
            needsDisplay = true
        }
    }
    var blinkOn = true {
        didSet {
            pulseOn = blinkOn
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        blinkTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncBlinkTimer()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color: NSColor
        if isRunning {
            color = pulseOn ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(0.26)
        } else {
            color = NSColor.systemRed
        }
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
    }

    private func syncBlinkTimer() {
        guard window != nil, isRunning else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            pulseOn = true
            return
        }
        guard blinkTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            self.pulseOn.toggle()
            self.needsDisplay = true
        }
        blinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }
}

final class MenuRowView: NSView {
    private let dotView: StatusDotView?
    private let textField: NSTextField

    init(text: String, indent: CGFloat = 0, dotRunning: Bool? = nil, blinkOn: Bool = true) {
        let height: CGFloat = 28
        let width: CGFloat = 1160
        self.textField = NSTextField(labelWithString: text)
        if let dotRunning {
            let dot = StatusDotView(frame: NSRect(x: 12 + indent, y: 9, width: 10, height: 10))
            dot.isRunning = dotRunning
            dot.blinkOn = blinkOn
            self.dotView = dot
        } else {
            self.dotView = nil
        }
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        if let dotView {
            addSubview(dotView)
        }

        textField.frame = NSRect(
            x: 16 + indent + (dotRunning == nil ? 0 : 18),
            y: 3,
            width: width - 28 - indent,
            height: 22
        )
        textField.font = NSFont.systemFont(ofSize: 14, weight: dotRunning == nil ? .regular : .semibold)
        textField.lineBreakMode = .byTruncatingTail
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(text: String, dotRunning: Bool? = nil, blinkOn: Bool = true) {
        textField.stringValue = text
        if let dotRunning, let dotView {
            dotView.isRunning = dotRunning
            dotView.blinkOn = blinkOn
        }
    }
}

final class FloatingBuildWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private let textView = NSTextView()
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(
        hookStates: [BuildHookState],
        inferredElapsed: TimeInterval?,
        inferredSummary: String,
        builds: [BuildRecord]
    ) {
        guard isVisible else {
            return
        }
        textView.string = content(
            hookStates: hookStates,
            inferredElapsed: inferredElapsed,
            inferredSummary: inferredSummary,
            builds: builds
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 280, y: 220, width: 760, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "XBT 编译实时看板"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let scrollView = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.windowBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView

        panel.contentView = scrollView
        textView.string = "等待 Xcode 构建记录\n\n配置 Scheme Hook 后，这里会实时显示正在编译的工程、设备和耗时。"
        return panel
    }

    private func content(
        hookStates: [BuildHookState],
        inferredElapsed: TimeInterval?,
        inferredSummary: String,
        builds: [BuildRecord]
    ) -> String {
        var lines: [String] = []
        let runningStates = hookStates.filter(\.isRunning)
        let now = formatter.string(from: Date())

        lines.append("XBT 编译实时看板")
        lines.append("最后刷新：\(now)")
        lines.append("")

        if !runningStates.isEmpty {
            lines.append(runningStates.count > 1 ? "正在编译：\(runningStates.count) 个会话" : "正在编译：1 个会话")
            appendHookStates(hookStates, to: &lines)
        } else if let inferredElapsed {
            lines.append("疑似正在编译")
            lines.append("推断耗时：~\(formatDuration(inferredElapsed))")
            if !inferredSummary.isEmpty {
                lines.append("进程：\(inferredSummary)")
            }
            lines.append("提示：配置 Scheme Hook 后可获得精准计时。")
        } else {
            lines.append("当前状态：未检测到正在编译")
        }

        lines.append("")
        lines.append("最近构建")
        if builds.isEmpty {
            lines.append("  暂无可展示记录。")
        } else {
            for build in builds.prefix(10) {
                let cost = build.duration.map { formatDuration($0) } ?? "待推断"
                lines.append("  \(formatter.string(from: build.modifiedAt))  \(build.project)  \(cost)  \(build.status)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func appendHookStates(_ states: [BuildHookState], to lines: inout [String]) {
        let visibleStates = Array(states.prefix(20))
        let groupedStates = Dictionary(grouping: visibleStates) { state in
            "\(state.project)|\(state.scheme)"
        }
        let orderedGroups = groupedStates.values.sorted { lhs, rhs in
            let lhsRunning = lhs.contains(where: \.isRunning)
            let rhsRunning = rhs.contains(where: \.isRunning)
            if lhsRunning != rhsRunning {
                return lhsRunning && !rhsRunning
            }
            let lhsName = "\(lhs.first?.project ?? "")/\(lhs.first?.scheme ?? "")"
            let rhsName = "\(rhs.first?.project ?? "")/\(rhs.first?.scheme ?? "")"
            return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
        }

        for group in orderedGroups {
            guard let first = group.first else {
                continue
            }
            let sortedGroup = group.sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return (lhs.elapsed ?? 0) > (rhs.elapsed ?? 0)
            }
            let runningCount = sortedGroup.filter(\.isRunning).count
            lines.append("")
            lines.append("● \(first.project) / \(first.scheme)（\(runningCount) 个进行中）")
            for state in sortedGroup {
                let elapsedText = state.elapsed.map { formatDuration($0) } ?? "未知"
                let statusText = state.isRunning ? "进行中" : "已结束"
                let destination = [state.destinationName, state.destinationID].filter { !$0.isEmpty }.joined(separator: " / ")
                lines.append("  \(statusText) \(elapsedText)")
                lines.append("  配置：\(state.config)")
                if !state.sdk.isEmpty || !state.platform.isEmpty {
                    lines.append("  SDK：\(state.sdk) \(state.platform)")
                }
                if !destination.isEmpty {
                    lines.append("  设备：\(destination)")
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(Int(seconds.rounded()), 0)
        let h = value / 3600
        let m = (value % 3600) / 60
        let s = value % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

final class SchemeCandidateBox: NSObject {
    let documentPath: String
    let schemePath: String
    let schemeName: String

    init(documentPath: String, schemePath: String, schemeName: String) {
        self.documentPath = documentPath
        self.schemePath = schemePath
        self.schemeName = schemeName
    }
}

struct XcodeDocumentSchemes {
    let path: String
    let displayName: String
    let schemes: [SchemeCandidateBox]
}

final class SchemeHookConfigurator {
    private let fileManager = FileManager.default
    private let hookScript = NSString(string: "~/.xcode-build-timer/xbt-build-hook.sh").expandingTildeInPath
    private var cachedAt = Date.distantPast
    private var cachedDocuments: [XcodeDocumentSchemes] = []

    func currentDocuments() -> [XcodeDocumentSchemes] {
        if Date().timeIntervalSince(cachedAt) < 10 {
            return cachedDocuments
        }

        cachedDocuments = loadCurrentDocuments()
        cachedAt = Date()
        return cachedDocuments
    }

    func configure(_ candidate: SchemeCandidateBox) throws -> String {
        let schemeURL = URL(fileURLWithPath: candidate.schemePath)
        let original = try String(contentsOf: schemeURL, encoding: .utf8)
        let updated = try configuredSchemeXML(from: original)

        if updated == original {
            return "已配置，无需重复修改：\(candidate.schemeName)"
        }

        try updated.write(to: schemeURL, atomically: true, encoding: .utf8)

        return "已配置：\(candidate.schemeName)"
    }

    private func loadCurrentDocuments() -> [XcodeDocumentSchemes] {
        let paths = openXcodeDocumentPaths()
            .filter { path in
                path.hasSuffix(".xcworkspace") || path.hasSuffix(".xcodeproj")
            }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard !seen.contains(path) else {
                return nil
            }
            seen.insert(path)

            let schemes = schemeCandidates(for: path)
            return XcodeDocumentSchemes(
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                schemes: schemes
            )
        }
    }

    private func openXcodeDocumentPaths() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e", "tell application \"Xcode\" to set docPaths to path of documents",
            "-e", "set AppleScript's text item delimiters to linefeed",
            "-e", "return docPaths as text"
        ]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            let deadline = Date().addingTimeInterval(2)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if task.isRunning {
                task.terminate()
                return []
            }
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func schemeCandidates(for documentPath: String) -> [SchemeCandidateBox] {
        let documentURL = URL(fileURLWithPath: documentPath)
        var candidateURLs: [URL] = []

        candidateURLs.append(contentsOf: schemeURLs(in: documentURL))

        let root = documentURL.deletingLastPathComponent()
        if documentURL.pathExtension == "xcworkspace" {
            if let children = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for child in children where child.pathExtension == "xcodeproj" && child.lastPathComponent != "Pods.xcodeproj" {
                    candidateURLs.append(contentsOf: schemeURLs(in: child))
                }
            }
        }

        let uniqueURLs = Array(Set(candidateURLs.map(\.path))).sorted()
        return uniqueURLs
            .filter { !$0.contains("/Pods/") && !$0.contains("Pods.xcodeproj") }
            .map { path in
                SchemeCandidateBox(
                    documentPath: documentPath,
                    schemePath: path,
                    schemeName: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                )
            }
    }

    private func schemeURLs(in containerURL: URL) -> [URL] {
        var urls: [URL] = []
        let sharedDir = containerURL.appendingPathComponent("xcshareddata/xcschemes", isDirectory: true)
        urls.append(contentsOf: xcschemes(in: sharedDir))

        let userDataDir = containerURL.appendingPathComponent("xcuserdata", isDirectory: true)
        if let userDirs = try? fileManager.contentsOfDirectory(at: userDataDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for userDir in userDirs where userDir.pathExtension == "xcuserdatad" {
                urls.append(contentsOf: xcschemes(in: userDir.appendingPathComponent("xcschemes", isDirectory: true)))
            }
        }
        return urls
    }

    private func xcschemes(in dir: URL) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return files.filter { $0.pathExtension == "xcscheme" }
    }

    private func configuredSchemeXML(from original: String) throws -> String {
        var xml = removeExistingXBTActions(from: original)
        let buildableReference = firstBuildableReference(from: xml)
        xml = try insertAction(named: "PreActions", scriptArgument: "start", buildableReference: buildableReference, into: xml)
        xml = try insertAction(named: "PostActions", scriptArgument: "end", buildableReference: buildableReference, into: xml)
        return xml
    }

    private func firstBuildableReference(from xml: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<BuildableReference\b(?:(?!</BuildableReference>).)*</BuildableReference>"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let match = regex.firstMatch(in: xml, options: [], range: range), let swiftRange = Range(match.range, in: xml) else {
            return nil
        }
        return String(xml[swiftRange])
    }

    private func removeExistingXBTActions(from xml: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*<ExecutionAction\b(?:(?!</ExecutionAction>).)*xbt-build-hook\.sh(?:(?!</ExecutionAction>).)*</ExecutionAction>"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return xml
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")
    }

    private func insertAction(named containerName: String, scriptArgument: String, buildableReference: String?, into xml: String) throws -> String {
        let action = executionActionXML(scriptArgument: scriptArgument, buildableReference: buildableReference)
        if let closeRange = xml.range(of: "</\(containerName)>") {
            var result = xml
            result.insert(contentsOf: action, at: closeRange.lowerBound)
            return result
        }

        let containerXML = "\n      <\(containerName)>\(action)\n      </\(containerName)>"
        guard let buildActionStart = xml.range(of: #"<BuildAction\b[^>]*>"#, options: .regularExpression) else {
            throw NSError(domain: "XBT", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到 BuildAction，无法配置 Scheme。"])
        }

        var result = xml
        if containerName == "PreActions" {
            result.insert(contentsOf: containerXML, at: buildActionStart.upperBound)
        } else if let buildActionEnd = result.range(of: "</BuildAction>") {
            result.insert(contentsOf: containerXML, at: buildActionEnd.lowerBound)
        } else {
            throw NSError(domain: "XBT", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到 BuildAction 结束标签，无法配置 Scheme。"])
        }
        return result
    }

    private func executionActionXML(scriptArgument: String, buildableReference: String?) -> String {
        let script = xmlEscape("\"\(hookScript)\" \(scriptArgument)")
        let title = scriptArgument == "start" ? "XBT Build Timer Start" : "XBT Build Timer End"
        let environmentBuildable: String
        if let buildableReference {
            environmentBuildable = """

               <EnvironmentBuildable>
                  \(buildableReference)
               </EnvironmentBuildable>
"""
        } else {
            environmentBuildable = ""
        }
        return """

         <ExecutionAction
            ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            <ActionContent
               title = "\(title)"
               scriptText = "\(script)">
\(environmentBuildable)
            </ActionContent>
         </ExecutionAction>
"""
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

final class BuildProcessReader {
    private struct RunningBuildToolSample {
        let toolName: String
        let buildRoot: URL
        let projectName: String
    }

    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var previousSizes: [String: UInt64] = [:]

    func currentActivity(excludingProjects excludedProjects: Set<String> = []) -> InferredBuildActivity {
        let samples = runningBuildToolSamples()
            .filter { sample in
                !excludedProjects.contains { excluded in
                    sample.projectName == excluded || sample.projectName.hasPrefix("\(excluded)-")
                }
            }

        guard !samples.isEmpty else {
            resetSnapshots()
            return InferredBuildActivity(isActive: false, summary: "")
        }

        var grewRoots: [String] = []
        var toolNames: [String] = []
        var nextSizes: [String: UInt64] = [:]

        for root in Array(Set(samples.map(\.buildRoot.path))).sorted() {
            let size = recentBuildOutputSize(at: URL(fileURLWithPath: root))
            nextSizes[root] = size
            if let previousSize = previousSizes[root], size > previousSize {
                grewRoots.append(root)
            }
        }

        if !grewRoots.isEmpty {
            let grewRootSet = Set(grewRoots)
            toolNames = samples
                .filter { grewRootSet.contains($0.buildRoot.path) }
                .map(\.toolName)
        }

        lock.lock()
        previousSizes = nextSizes
        lock.unlock()

        guard !grewRoots.isEmpty else {
            return InferredBuildActivity(isActive: false, summary: "")
        }

        let summary = Array(Set(toolNames)).sorted().joined(separator: ", ")
        return InferredBuildActivity(isActive: true, summary: summary.isEmpty ? "Build output growing" : summary)
    }

    func activeProjectNames() -> Set<String> {
        Set(runningBuildToolSamples().map(\.projectName))
    }

    private func resetSnapshots() {
        lock.lock()
        previousSizes.removeAll()
        lock.unlock()
    }

    private func runningBuildToolSamples() -> [RunningBuildToolSample] {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["axo", "args="]
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                return []
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return []
            }
            return text
                .split(separator: "\n")
                .compactMap { buildToolSample(from: String($0)) }
        } catch {
            return []
        }
    }

    private func buildToolSample(from processLine: String) -> RunningBuildToolSample? {
        let trimmed = processLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let command = parts.first else {
            return nil
        }

        let name = URL(fileURLWithPath: String(command)).lastPathComponent
        let args = trimmed
        let buildToolNames: Set<String> = [
            "clang",
            "clang++",
            "swift-frontend",
            "swiftc",
            "ibtool",
            "actool",
            "ld",
            "builtin-copy",
            "builtin-infoPlistUtility"
        ]

        guard buildToolNames.contains(name) else {
            return nil
        }

        if args.contains(" -fsyntax-only ") || args.hasSuffix(" -fsyntax-only") {
            return nil
        }

        let isDerivedDataBuild = args.contains("/DerivedData/") && args.contains("/Build/")
        let isXcodeBuildStep = args.contains("/Build/Intermediates.noindex/") || args.contains("/Build/Products/")
        guard isDerivedDataBuild && isXcodeBuildStep else {
            return nil
        }

        guard let buildRoot = buildRootURL(from: args) else {
            return nil
        }

        let derivedDataName = buildRoot.deletingLastPathComponent().lastPathComponent
        return RunningBuildToolSample(
            toolName: name,
            buildRoot: buildRoot,
            projectName: normalizedProjectName(from: derivedDataName)
        )
    }

    private func normalizedProjectName(from derivedDataName: String) -> String {
        guard let dashIndex = derivedDataName.lastIndex(of: "-") else {
            return derivedDataName
        }
        let suffix = derivedDataName[derivedDataName.index(after: dashIndex)...]
        if suffix.count >= 16 && suffix.allSatisfy({ $0.isLetter || $0.isNumber }) {
            return String(derivedDataName[..<dashIndex])
        }
        return derivedDataName
    }

    private func buildRootURL(from args: String) -> URL? {
        guard let derivedDataRange = args.range(of: "/DerivedData/") else {
            return nil
        }

        let prefix = String(args[..<derivedDataRange.upperBound])
        let suffix = args[derivedDataRange.upperBound...]
        guard let projectComponent = suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return nil
        }

        return URL(fileURLWithPath: "\(prefix)\(projectComponent)/Build", isDirectory: true)
    }

    private func recentBuildOutputSize(at root: URL) -> UInt64 {
        let recentThreshold = Date().addingTimeInterval(-120)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        var scanned = 0
        for case let url as URL in enumerator {
            scanned += 1
            if scanned > 30_000 {
                break
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= recentThreshold,
                  let fileSize = values.fileSize,
                  fileSize > 0 else {
                continue
            }
            total += UInt64(fileSize)
        }
        return total
    }
}

final class BuildLogReader {
    private let fileManager = FileManager.default
    private let derivedData = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
    private var recordCache: [String: (modifiedAt: Date, record: BuildRecord)] = [:]

    func recentBuilds(limit: Int = 20, after clearedBefore: Date? = nil) -> [BuildRecord] {
        let urls = buildLogURLs()
        return urls
            .sorted { modifiedDate($0) > modifiedDate($1) }
            .filter { url in
                guard let clearedBefore else {
                    return true
                }
                return modifiedDate(url) > clearedBefore
            }
            .prefix(limit)
            .map { record(for: $0) }
    }

    private func buildLogURLs() -> [URL] {
        let root = URL(fileURLWithPath: derivedData)
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for projectDir in projectDirs {
            let buildLogDir = projectDir.appendingPathComponent("Logs/Build", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: buildLogDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files where file.pathExtension == "xcactivitylog" {
                urls.append(file)
            }
        }
        return urls
    }

    private func record(for url: URL) -> BuildRecord {
        let modifiedAt = modifiedDate(url)
        if let cached = recordCache[url.path], cached.modifiedAt == modifiedAt {
            return cached.record
        }

        let text = activityText(from: url)
        let duration = extractBuildDuration(from: text) ?? extractDuration(from: text) ?? estimateDuration(from: url, text: text)
        let status = extractStatus(from: text)
        let project = projectName(from: url)

        let record = BuildRecord(
            project: project,
            logPath: url.path,
            modifiedAt: modifiedAt,
            duration: duration,
            status: status,
            slowSwift: extractInterestingLines(from: text, markers: ["CompileSwift", "SwiftCompile", "swift-frontend"], limit: 5),
            slowScripts: extractInterestingLines(from: text, markers: ["PhaseScriptExecution", "Run Script"], limit: 5),
            slowTargets: extractInterestingLines(from: text, markers: ["Building target", "Build target", "Target "], limit: 5)
        )
        recordCache[url.path] = (modifiedAt, record)
        return record
    }

    private func extractBuildDuration(from text: String) -> TimeInterval? {
        guard let regex = try? NSRegularExpression(pattern: #""wcStartTime"\s*:\s*(\d+)"#) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var minValue: Double?
        var maxValue: Double?

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1, let swiftRange = Range(match.range(at: 1), in: text), let value = Double(text[swiftRange]) else {
                return
            }
            minValue = min(minValue ?? value, value)
            maxValue = max(maxValue ?? value, value)
        }

        guard let minValue, let maxValue, maxValue > minValue else {
            return nil
        }

        let seconds = (maxValue - minValue) / 1_000_000
        guard seconds > 0, seconds < 86_400 else {
            return nil
        }
        return seconds
    }

    private func activityText(from url: URL) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        task.arguments = ["-dc", url.path]

        let gzipOutput = Pipe()
        let gzipError = Pipe()
        task.standardOutput = gzipOutput
        task.standardError = gzipError

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        let data = gzipOutput.fileHandleForReading.readDataToEndOfFile()
        if data.isEmpty {
            return ""
        }

        return printableStrings(from: data)
    }

    private func printableStrings(from data: Data) -> String {
        var lines: [String] = []
        var buffer = [UInt8]()

        func flush() {
            guard buffer.count >= 4 else {
                buffer.removeAll(keepingCapacity: true)
                return
            }
            if let line = String(bytes: buffer, encoding: .utf8) {
                let cleaned = line
                    .replacingOccurrences(of: "\u{0}", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    lines.append(cleaned)
                }
            }
            buffer.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if byte >= 32 && byte <= 126 {
                buffer.append(byte)
            } else {
                flush()
            }
        }
        flush()

        return lines.joined(separator: "\n")
    }

    private func extractDuration(from text: String) -> TimeInterval? {
        let patterns = [
            #"([0-9]+(?:\.[0-9]+)?)\s*s(?:ec(?:onds?)?)?\b"#,
            #"duration[^0-9]{0,12}([0-9]+(?:\.[0-9]+)?)"#
        ]

        var candidates: [Double] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1, let swiftRange = Range(match.range(at: 1), in: text) else {
                    return
                }
                if let value = Double(text[swiftRange]), value > 0, value < 86_400 {
                    candidates.append(value)
                }
            }
        }

        return candidates.max()
    }

    private func estimateDuration(from url: URL, text: String) -> TimeInterval? {
        let sizeFactor = Double(max(text.count, 1)) / 75_000.0
        if sizeFactor > 1 {
            return min(max(sizeFactor, 1), 3_600)
        }
        return nil
    }

    private func extractStatus(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("build failed") || lower.contains("failed") {
            return "失败"
        }
        if lower.contains("cancelled") || lower.contains("canceled") {
            return "取消"
        }
        if lower.contains("build succeeded") || lower.contains("succeeded") {
            return "成功"
        }
        return "未知"
    }

    private func extractInterestingLines(from text: String, markers: [String], limit: Int) -> [String] {
        var result: [String] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let compact = line
                .replacingOccurrences(of: #"[\s]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !compact.isEmpty else {
                continue
            }
            if markers.contains(where: { compact.localizedCaseInsensitiveContains($0) }) {
                result.append(shorten(compact, to: 92))
            }
            if result.count >= limit {
                break
            }
        }

        return Array(NSOrderedSet(array: result)) as? [String] ?? result
    }

    private func modifiedDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func projectName(from url: URL) -> String {
        let parts = url.pathComponents
        if let index = parts.firstIndex(of: "DerivedData"), parts.indices.contains(index + 1) {
            let folder = parts[index + 1]
            if let range = folder.range(of: "-", options: .backwards) {
                return String(folder[..<range.lowerBound])
            }
            return folder
        }
        return "Unknown"
    }

    private func shorten(_ value: String, to limit: Int) -> String {
        if value.count <= limit {
            return value
        }
        return String(value.prefix(limit - 1)) + "…"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let clearedBeforeKey = "clearedBefore"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateReader = BuildStateReader()
    private let processReader = BuildProcessReader()
    private let schemeConfigurator = SchemeHookConfigurator()
    private let floatingWindow = FloatingBuildWindowController()
    private let reader = BuildLogReader()
    private let refreshQueue = DispatchQueue(label: "local.jobs.XcodeBuildTimer.refresh", qos: .userInitiated)
    private let logRefreshQueue = DispatchQueue(label: "local.jobs.XcodeBuildTimer.log-refresh", qos: .utility)
    private var currentMenu = NSMenu()
    private var hookRowViews: [String: MenuRowView] = [:]
    private var isMenuOpen = false
    private var blinkOn = true
    private var isRefreshing = false
    private var isRefreshingLogs = false
    private var refreshStartedAt: Date?
    private var inferredBuildStart: Date?
    private var inferredBuildLastSeen: Date?
    private var inferredBuildSummary = ""
    private var hookInactiveSince: [String: Date] = [:]
    private var suppressTimingUntilIdle = false
    private var timerWasManuallyCleared = false
    private var cachedBuilds: [BuildRecord] = []
    private var lastLogRefresh = Date.distantPast
    private let runtimeLog = NSString(string: "~/.xcode-build-timer/runtime.log").expandingTildeInPath
    private var refreshTimer: Timer?
    private var logRefreshTimer: Timer?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        writeRuntimeLog("appDidFinishLaunching")
        if let button = statusItem.button {
            button.title = "⏱XBT"
            button.toolTip = "Xcode 编译耗时"
        }

        currentMenu.delegate = self
        statusItem.menu = currentMenu
        replaceCurrentMenu(with: makeMenu(builds: [], isLoading: false))
        requestRefresh()
        refreshTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.requestRefresh()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }

        logRefreshTimer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.requestLogRefresh()
        }
        if let logRefreshTimer {
            RunLoop.main.add(logRefreshTimer, forMode: .common)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    private func requestRefresh() {
        if isRefreshing {
            if let refreshStartedAt, Date().timeIntervalSince(refreshStartedAt) < 2 {
                writeRuntimeLog("requestRefresh skipped")
                return
            }
            writeRuntimeLog("requestRefresh recovered stale refresh")
            isRefreshing = false
        }
        writeRuntimeLog("requestRefresh start")
        isRefreshing = true
        refreshStartedAt = Date()

        refreshQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.writeRuntimeLog("refreshQueue entered")
            let activeProjects = self.processReader.activeProjectNames()
            let initialHookStates = self.stateReader.currentStates()
            let didReviveState = self.reviveAutoFinishedHookStates(initialHookStates, activeProjects: activeProjects)
            let rawHookStates = didReviveState ? self.stateReader.currentStates() : initialHookStates
            let hookProjects = Set(rawHookStates.filter(\.isRunning).map(\.project))
            let shouldSuppressTiming = self.suppressTimingUntilIdle && (!activeProjects.isEmpty || rawHookStates.contains(where: \.isRunning))
            let inferredActivity = shouldSuppressTiming
                ? InferredBuildActivity(isActive: false, summary: "")
                : self.processReader.currentActivity(excludingProjects: hookProjects)
            let builds = self.cachedBuilds
            DispatchQueue.main.async {
                if self.suppressTimingUntilIdle && activeProjects.isEmpty && !rawHookStates.contains(where: \.isRunning) {
                    self.suppressTimingUntilIdle = false
                    self.timerWasManuallyCleared = false
                }
                let hookStates = shouldSuppressTiming ? [] : self.resolveStaleHookStates(rawHookStates, activeProjects: activeProjects)
                let runningStates = hookStates.filter(\.isRunning)
                self.updateInferredActivity(inferredActivity)
                let inferredElapsed = self.inferredBuildStart.map { Date().timeIntervalSince($0) }
                self.blinkOn.toggle()
                self.floatingWindow.update(
                    hookStates: hookStates,
                    inferredElapsed: inferredElapsed,
                    inferredSummary: self.inferredBuildSummary,
                    builds: builds
                )
                if !self.isMenuOpen {
                    self.replaceCurrentMenu(
                        with: self.makeMenu(
                            builds: builds,
                            hookStates: hookStates,
                            inferredElapsed: inferredElapsed,
                            inferredSummary: self.inferredBuildSummary,
                            isLoading: false
                        )
                    )
                }
                let runningCount = runningStates.count + (inferredElapsed == nil ? 0 : 1)
                let nextStatusTitle: String
                if let runningState = runningStates.max(by: { ($0.elapsed ?? 0) < ($1.elapsed ?? 0) }), let elapsed = runningState.elapsed {
                    nextStatusTitle = runningCount > 1 ? "⏱\(self.formatDuration(elapsed))×\(runningCount)" : "⏱\(self.formatDuration(elapsed))"
                } else if let inferredElapsed {
                    nextStatusTitle = "⏱~\(self.formatDuration(inferredElapsed))"
                } else if let hookState = hookStates.first, let elapsed = hookState.elapsed {
                    nextStatusTitle = "⏱\(self.formatDuration(elapsed))"
                } else if !self.timerWasManuallyCleared, let latest = builds.first {
                    nextStatusTitle = latest.duration.map { "⏱\(self.formatDuration($0))" } ?? "⏱XBT"
                } else {
                    nextStatusTitle = "⏱XBT"
                }
                if !self.isMenuOpen {
                    self.statusItem.button?.title = nextStatusTitle
                }
                self.writeRuntimeLog(
                    "hookRunning=\(!runningStates.isEmpty) activeProjects=\(Array(activeProjects).sorted().joined(separator: ",")) suppress=\(shouldSuppressTiming) inferred=\(inferredActivity.isActive) inferredSummary=\(inferredActivity.summary) title=\(nextStatusTitle)"
                )
                self.isRefreshing = false
                self.refreshStartedAt = nil
            }
        }
    }

    private func resolveStaleHookStates(_ states: [BuildHookState], activeProjects: Set<String>) -> [BuildHookState] {
        let now = Date()
        var didFinishState = false

        for state in states where state.isRunning {
            if hookState(state, matchesAny: activeProjects) {
                hookInactiveSince.removeValue(forKey: state.key)
                continue
            }

            let inactiveSince = hookInactiveSince[state.key] ?? now
            hookInactiveSince[state.key] = inactiveSince
            if now.timeIntervalSince(inactiveSince) >= 15 {
                if let startEpoch = state.startEpoch, now.timeIntervalSince1970 - startEpoch > 1_800 {
                    stateReader.discardState(state, reason: "discard-stale-running-state")
                    writeRuntimeLog("discardedStaleHook project=\(state.project) scheme=\(state.scheme)")
                } else {
                    stateReader.finishRunningState(
                        state,
                        reason: "no-build-process-after-failure-or-cancel",
                        endEpoch: inactiveSince.timeIntervalSince1970
                    )
                    writeRuntimeLog("autoFinishedStaleHook project=\(state.project) scheme=\(state.scheme)")
                }
                hookInactiveSince.removeValue(forKey: state.key)
                didFinishState = true
            }
        }

        let activeKeys = Set(states.map(\.key))
        hookInactiveSince = hookInactiveSince.filter { activeKeys.contains($0.key) }

        return didFinishState ? stateReader.currentStates() : states
    }

    private func hookState(_ state: BuildHookState, matchesAny activeProjects: Set<String>) -> Bool {
        activeProjects.contains { activeProject in
            activeProject == state.project || activeProject.hasPrefix("\(state.project)-")
        }
    }

    private func reviveAutoFinishedHookStates(_ states: [BuildHookState], activeProjects: Set<String>) -> Bool {
        var didRevive = false
        for state in states where !state.isRunning
            && state.finishReason == "no-build-process-after-failure-or-cancel"
            && hookState(state, matchesAny: activeProjects) {
            stateReader.reviveAutoFinishedState(state)
            didRevive = true
            writeRuntimeLog("revivedAutoFinishedHook project=\(state.project) scheme=\(state.scheme)")
        }
        return didRevive
    }

    private func requestLogRefresh() {
        guard !isRefreshingLogs else {
            return
        }
        isRefreshingLogs = true

        logRefreshQueue.async { [weak self] in
            guard let self else {
                return
            }
            let hookStates = self.stateReader.currentStates()
            let hookProjects = Set(hookStates.filter(\.isRunning).map(\.project))
            let inferredActivity = self.processReader.currentActivity(excludingProjects: hookProjects)
            if hookStates.contains(where: \.isRunning) || inferredActivity.isActive {
                DispatchQueue.main.async {
                    self.isRefreshingLogs = false
                }
                return
            }

            let builds = self.reader.recentBuilds(limit: 20, after: self.clearedBeforeDate())
            DispatchQueue.main.async {
                self.cachedBuilds = builds
                self.lastLogRefresh = Date()
                if !self.isMenuOpen {
                    self.replaceCurrentMenu(with: self.makeMenu(builds: builds, isLoading: false))
                }
                self.isRefreshingLogs = false
            }
        }
    }

    private func writeRuntimeLog(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(timestamp)] \(line)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: runtimeLog),
               let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: runtimeLog)) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
                _ = try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: runtimeLog))
            }
        }
    }

    private func updateInferredActivity(_ activity: InferredBuildActivity) {
        if activity.isActive {
            if inferredBuildStart == nil {
                inferredBuildStart = Date()
            }
            inferredBuildLastSeen = Date()
            inferredBuildSummary = activity.summary
            return
        }

        if let lastSeen = inferredBuildLastSeen, Date().timeIntervalSince(lastSeen) <= 3 {
            return
        }

        inferredBuildStart = nil
        inferredBuildLastSeen = nil
        inferredBuildSummary = ""
    }

    private func makeMenu(
        builds: [BuildRecord]?,
        hookStates: [BuildHookState] = [],
        inferredElapsed: TimeInterval? = nil,
        inferredSummary: String = "",
        isLoading: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.minimumWidth = 360

        if isLoading {
            menu.addItem(NSMenuItem(title: "正在自动读取 Xcode 构建日志", action: nil, keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(actionItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
            return finalizeMenu(menu)
        }

        let builds = builds ?? []
        if !hookStates.isEmpty {
            appendHookStates(hookStates, to: menu)
            if let inferredElapsed {
                menu.addItem(.separator())
                appendInferredState(elapsed: inferredElapsed, summary: inferredSummary, to: menu)
            }
            menu.addItem(.separator())
        } else if let inferredElapsed {
            appendInferredState(elapsed: inferredElapsed, summary: inferredSummary, to: menu)
            menu.addItem(.separator())
        }

        if builds.isEmpty {
            menu.addItem(detailRowItem(title: "等待 Xcode 构建记录"))
            menu.addItem(detailRowItem(title: "工具会自动读取 DerivedData/Logs/Build"))
            menu.addItem(detailRowItem(title: "精准动态计时需要配置 Scheme Hook"))
            menu.addItem(actionItem(title: "打开悬浮窗", action: #selector(openFloatingWindow)))
            menu.addItem(.separator())
            appendSchemeHookMenu(to: menu)
            menu.addItem(actionItem(title: "~/Library/Developer/Xcode/DerivedData", action: #selector(openDerivedData)))
            menu.addItem(.separator())
            menu.addItem(actionItem(title: "清除计时", action: #selector(clearTimer)))
            menu.addItem(actionItem(title: "清除历史记录", action: #selector(clearHistory)))
            menu.addItem(.separator())
            menu.addItem(actionItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
            return finalizeMenu(menu)
        }

        let latest = builds[0]

        menu.addItem(NSMenuItem(title: "最近构建", action: nil, keyEquivalent: ""))
        for build in builds.prefix(8) {
            let item = actionItem(title: buildTitle(build), action: #selector(openLog(_:)))
            item.representedObject = build.logPath
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "趋势", action: nil, keyEquivalent: ""))
        for line in trendLines(builds) {
            menu.addItem(NSMenuItem(title: line, action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        appendSection("慢 Swift 编译项", latest.slowSwift, to: menu)
        appendSection("慢脚本阶段", latest.slowScripts, to: menu)
        appendSection("疑似慢 target", latest.slowTargets, to: menu)

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "打开悬浮窗", action: #selector(openFloatingWindow)))
        appendSchemeHookMenu(to: menu)
        menu.addItem(actionItem(title: "打开 DerivedData", action: #selector(openDerivedData)))
        menu.addItem(actionItem(title: "清除计时", action: #selector(clearTimer)))
        menu.addItem(actionItem(title: "清除历史记录", action: #selector(clearHistory)))
        menu.addItem(actionItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        return finalizeMenu(menu)
    }

    private func replaceCurrentMenu(with newMenu: NSMenu) {
        currentMenu.minimumWidth = newMenu.minimumWidth
        currentMenu.removeAllItems()
        while let item = newMenu.items.first {
            newMenu.removeItem(item)
            currentMenu.addItem(item)
        }
    }

    private func appendSchemeHookMenu(to menu: NSMenu) {
        let rootItem = NSMenuItem(title: "配置 Scheme Hook", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let documents = schemeConfigurator.currentDocuments()

        if documents.isEmpty {
            submenu.addItem(detailRowItem(title: "未发现 Xcode 打开的工程"))
            submenu.addItem(detailRowItem(title: "请先在 Xcode 打开 .xcworkspace/.xcodeproj"))
        } else {
            for document in documents {
                let docItem = NSMenuItem(title: document.displayName, action: nil, keyEquivalent: "")
                let docMenu = NSMenu()
                if document.schemes.isEmpty {
                    docMenu.addItem(detailRowItem(title: "未找到可配置 Scheme"))
                } else {
                    for scheme in document.schemes {
                        let schemeItem = actionItem(title: scheme.schemeName, action: #selector(configureSchemeHook(_:)))
                        schemeItem.representedObject = scheme
                        docMenu.addItem(schemeItem)
                    }
                }
                docItem.submenu = docMenu
                submenu.addItem(docItem)
            }
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
        menu.addItem(.separator())
    }

    private func appendHookStates(_ states: [BuildHookState], to menu: NSMenu) {
        let runningCount = states.filter(\.isRunning).count
        if runningCount > 0 {
            menu.addItem(NSMenuItem(title: runningCount > 1 ? "正在编译（\(runningCount) 个会话）" : "正在编译", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "最近 Hook 计时", action: nil, keyEquivalent: ""))
        }

        let visibleStates = Array(states.prefix(8))
        let groupedStates = Dictionary(grouping: visibleStates) { state in
            "\(state.project)|\(state.scheme)"
        }
        let orderedGroups = groupedStates.values.sorted { lhs, rhs in
            let lhsRunning = lhs.contains(where: \.isRunning)
            let rhsRunning = rhs.contains(where: \.isRunning)
            if lhsRunning != rhsRunning {
                return lhsRunning && !rhsRunning
            }
            let lhsName = "\(lhs.first?.project ?? "")/\(lhs.first?.scheme ?? "")"
            let rhsName = "\(rhs.first?.project ?? "")/\(rhs.first?.scheme ?? "")"
            return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
        }

        for (index, group) in orderedGroups.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }

            let sortedGroup = group.sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return (lhs.elapsed ?? 0) > (rhs.elapsed ?? 0)
            }
            guard let first = sortedGroup.first else {
                continue
            }

            let groupRunningCount = sortedGroup.filter(\.isRunning).count
            let groupTitle: String
            if groupRunningCount > 0 {
                groupTitle = "\(first.project) / \(first.scheme)（\(groupRunningCount) 个进行中）"
            } else {
                groupTitle = "\(first.project) / \(first.scheme)"
            }
            menu.addItem(rowItem(
                key: groupRowKey(for: first),
                title: groupTitle,
                dotRunning: groupRunningCount > 0,
                blinkOn: blinkOn
            ))

            for state in sortedGroup {
                menu.addItem(rowItem(
                    key: stateRowKey(for: state),
                    title: stateRowTitle(for: state),
                    indent: 14
                ))
                menu.addItem(detailRowItem(title: "配置：\(state.config)", indent: 28))
                if !state.sdk.isEmpty || !state.platform.isEmpty {
                    menu.addItem(detailRowItem(title: "SDK：\(state.sdk) \(state.platform)", indent: 28))
                }
            }
        }
    }

    private func rowItem(key: String, title: String, indent: CGFloat = 0, dotRunning: Bool? = nil, blinkOn: Bool = true) -> NSMenuItem {
        let item = NSMenuItem()
        let view = MenuRowView(text: title, indent: indent, dotRunning: dotRunning, blinkOn: blinkOn)
        item.view = view
        hookRowViews[key] = view
        return item
    }

    private func detailRowItem(title: String, indent: CGFloat = 0) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuRowView(text: title, indent: indent)
        return item
    }

    private func groupRowKey(for state: BuildHookState) -> String {
        "group|\(state.project)|\(state.scheme)"
    }

    private func stateRowKey(for state: BuildHookState) -> String {
        "state|\(state.key)"
    }

    private func stateRowTitle(for state: BuildHookState) -> String {
        let elapsedText = state.elapsed.map { formatDuration($0) } ?? "未知"
        let prefix = state.isRunning ? "进行中" : "已结束"
        let destination = [state.destinationName, state.destinationID].filter { !$0.isEmpty }.joined(separator: " / ")
        let destinationText = destination.isEmpty ? "未指定设备" : destination
        return "\(prefix) \(elapsedText)  \(destinationText)"
    }

    private func updateVisibleHookRows(_ states: [BuildHookState]) {
        let visibleStates = Array(states.prefix(8))
        let groupedStates = Dictionary(grouping: visibleStates) { state in
            "\(state.project)|\(state.scheme)"
        }

        for group in groupedStates.values {
            guard let first = group.first else {
                continue
            }
            let runningCount = group.filter(\.isRunning).count
            let title = runningCount > 0
                ? "\(first.project) / \(first.scheme)（\(runningCount) 个进行中）"
                : "\(first.project) / \(first.scheme)"
            hookRowViews[groupRowKey(for: first)]?.update(text: title, dotRunning: runningCount > 0, blinkOn: blinkOn)

            for state in group {
                hookRowViews[stateRowKey(for: state)]?.update(text: stateRowTitle(for: state))
            }
        }
    }

    private func appendInferredState(elapsed: TimeInterval, summary: String, to menu: NSMenu) {
        menu.addItem(detailRowItem(title: "疑似正在编译"))
        menu.addItem(detailRowItem(title: "推断耗时：~\(formatDuration(elapsed))"))
        if !summary.isEmpty {
            menu.addItem(detailRowItem(title: "进程：\(summary)"))
        }
        menu.addItem(detailRowItem(title: "提示：配置 Scheme Hook 后可获得精准计时"))
    }

    private func finalizeMenu(_ menu: NSMenu) -> NSMenu {
        let bottomSpacer = NSMenuItem()
        bottomSpacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 12))
        menu.addItem(bottomSpacer)
        return menu
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func appendSection(_ title: String, _ lines: [String], to menu: NSMenu) {
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        if lines.isEmpty {
            menu.addItem(NSMenuItem(title: "未从最新日志提取到相关片段", action: nil, keyEquivalent: ""))
            return
        }
        for line in lines {
            menu.addItem(NSMenuItem(title: "  " + line, action: nil, keyEquivalent: ""))
        }
    }

    private func buildTitle(_ build: BuildRecord) -> String {
        let time = formatter.string(from: build.modifiedAt)
        let cost = build.duration.map { formatDuration($0) } ?? "待推断"
        return "\(time)  \(build.project)  \(cost)  \(build.status)"
    }

    private func trendLines(_ builds: [BuildRecord]) -> [String] {
        let durations = builds.compactMap(\.duration)
        guard !durations.isEmpty else {
            return ["暂无可计算耗时"]
        }

        let avg = durations.reduce(0, +) / Double(durations.count)
        let maxValue = durations.max() ?? 0
        let minValue = durations.min() ?? 0
        let today = Calendar.current.startOfDay(for: Date())
        let todayCount = builds.filter { $0.modifiedAt >= today }.count

        return [
            "今日构建：\(todayCount) 次",
            "平均耗时：\(formatDuration(avg))",
            "最长耗时：\(formatDuration(maxValue))",
            "最短耗时：\(formatDuration(minValue))"
        ]
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let value = max(Int(seconds.rounded()), 0)
        let h = value / 3600
        let m = (value % 3600) / 60
        let s = value % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    @objc private func openLog(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func openFloatingWindow() {
        floatingWindow.show()
        requestRefresh()
    }

    @objc private func openDerivedData() {
        let path = NSString(string: "~/Library/Developer/Xcode/DerivedData").expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func configureSchemeHook(_ sender: NSMenuItem) {
        guard let candidate = sender.representedObject as? SchemeCandidateBox else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "配置 Scheme Hook？"
        alert.informativeText = "将直接更新：\n\(candidate.schemePath)\n\n不会创建 .xcscheme 备份；需要时可重新配置生成。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "配置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            let message = try schemeConfigurator.configure(candidate)
            showAlert(title: "配置完成", message: message, style: .informational)
        } catch {
            showAlert(title: "配置失败", message: error.localizedDescription, style: .critical)
        }
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func refreshFromMenu() {
        replaceCurrentMenu(with: makeMenu(builds: [], isLoading: false))
        requestRefresh()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清除历史记录？"
        alert.informativeText = "只会清空本工具菜单中的历史展示，不会删除 Xcode DerivedData 里的原始 .xcactivitylog。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: clearedBeforeKey)
            replaceCurrentMenu(with: makeMenu(builds: [], isLoading: false))
            requestRefresh()
        }
    }

    @objc private func clearTimer() {
        stateReader.clearTimingStates()
        inferredBuildStart = nil
        inferredBuildLastSeen = nil
        inferredBuildSummary = ""
        hookInactiveSince.removeAll()
        suppressTimingUntilIdle = true
        timerWasManuallyCleared = true
        statusItem.button?.title = "⏱XBT"
        replaceCurrentMenu(with: makeMenu(builds: cachedBuilds, isLoading: false))
        writeRuntimeLog("clearTimer")
        requestRefresh()
    }

    @objc private func showAllHistory() {
        UserDefaults.standard.removeObject(forKey: clearedBeforeKey)
        replaceCurrentMenu(with: makeMenu(builds: [], isLoading: false))
        requestRefresh()
    }

    private func clearedBeforeDate() -> Date? {
        let value = UserDefaults.standard.double(forKey: clearedBeforeKey)
        guard value > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: value)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
SWIFT_SOURCE

  success_echo "已写入 Swift 源码：${SOURCE_FILE}"
}

write_info_plist() {
  mkdir -p "$APP_CONTENTS" "$APP_MACOS"
  cat > "$APP_INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>local.jobs.${APP_NAME}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

  success_echo "已写入 App 配置：${APP_INFO_PLIST}"
}

compile_app() {
  local swiftc_path=""
  local sdk_path=""
  local arch_name=""
  local deployment_target="13.0"
  local swift_target=""

  swiftc_path="$(xcrun --find swiftc)"
  sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
  arch_name="$(uname -m)"
  swift_target="${arch_name}-apple-macosx${deployment_target}"

  info_echo "开始编译菜单栏工具。"
  gray_echo "Swift 编译器：${swiftc_path}"
  gray_echo "macOS SDK：${sdk_path}"
  gray_echo "编译目标：${swift_target}"

  MACOSX_DEPLOYMENT_TARGET="${deployment_target}" \
    "$swiftc_path" \
      -sdk "$sdk_path" \
      -target "$swift_target" \
      "$SOURCE_FILE" \
      -o "$APP_EXECUTABLE" \
      -framework Cocoa
  local compile_status=$?
  if [[ $compile_status -ne 0 ]]; then
    error_echo "编译失败，请查看日志：${LOG_FILE}"
    return $compile_status
  fi

  chmod +x "$APP_EXECUTABLE"
  success_echo "编译完成：${APP_BUNDLE}"
}

launch_app() {
  info_echo "启动菜单栏工具。"
  open -n "$APP_BUNDLE"
  local open_status=$?
  if [[ $open_status -ne 0 ]]; then
    error_echo "启动失败：${APP_BUNDLE}"
    return $open_status
  fi

  sleep 1
  if pgrep -f "$APP_EXECUTABLE" >/dev/null 2>&1; then
    success_echo "已启动。请在 macOS 菜单栏查看 ⏱XBT 或 ⏱耗时。"
  else
    error_echo "启动命令已执行，但未发现 ${APP_NAME} 进程。"
    return 1
  fi
}

show_scheme_hook_usage() {
  echo ""
  highlight_echo "=========================== Xcode Scheme Hook ==========================="
  note_echo "要启用精准动态计时，请在 Xcode Scheme 的 Build 动作里配置："
  gray_echo "1. Product -> Scheme -> Edit Scheme..."
  gray_echo "2. Build -> Pre-actions -> New Run Script Action"
  gray_echo "3. Build -> Post-actions -> New Run Script Action"
  gray_echo "4. 两个 Action 都建议选择 Provide build settings from 当前 App Target"
  gray_echo "5. 多项目、多 Scheme、多 SDK/设备会写入不同状态文件；菜单栏会优先显示正在编译的会话。"
  echo ""
  bold_echo "Pre-action 脚本："
  color_echo "\"${HOOK_SCRIPT}\" start"
  echo ""
  bold_echo "Post-action 脚本："
  color_echo "\"${HOOK_SCRIPT}\" end"
  echo ""
  gray_echo "配置后，菜单栏会在编译开始时每秒显示当前耗时；编译结束后显示本次总耗时。"
  highlight_echo "======================================================================="
}

ask_refresh_system_ui_if_needed() {
  echo ""
  warn_echo "如果右上角仍看不到 ⏱XBT，可以刷新 macOS 菜单栏 SystemUIServer。"
  gray_echo "这个动作会让右上角菜单栏图标短暂消失并自动恢复，不会重启电脑。"
  gray_echo "默认不执行；只有输入 YES 后回车才刷新。"
  local input=""
  IFS= read -r "input?➤ 是否刷新菜单栏？输入 YES 执行，其它输入跳过：" input
  if [[ "$input" == "YES" ]]; then
    info_echo "正在刷新 SystemUIServer。"
    killall SystemUIServer >/dev/null 2>&1 || true
    sleep 2
    open -n "$APP_BUNDLE"
    success_echo "菜单栏已刷新，并已重新打开 ${APP_NAME}。"
  else
    gray_echo "已跳过刷新菜单栏。"
  fi
}

main() {
  show_script_intro_and_wait
  init_runtime
  check_environment || return 1
  clean_running_environment || return 1
  write_hook_script || return 1
  write_swift_source || return 1
  write_info_plist || return 1
  compile_app || return 1
  launch_app || return 1
  show_scheme_hook_usage
  ask_refresh_system_ui_if_needed
  success_echo "全部完成。"
}

main "$@"
