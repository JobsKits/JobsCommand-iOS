//
//  AppModel.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var rootDirectoryPath = ""
    @Published var outputDirectoryPath = FileManager.default.urls(
        for: .downloadsDirectory,
        in: .userDomainMask
    ).first?.path ?? NSHomeDirectory()
    @Published var localSpecs: [PodSpecRecord] = []
    @Published var selectedRootName = ""
    @Published var resolutionRows: [DependencyResolutionRow] = []
    @Published var provenanceRows: [ProvenanceRow] = []
    @Published var stage: BuildStage = .idle
    @Published var statusMessage = "请拖入或选择统一管理的 JobsByPods 目录。"
    @Published var logText = ""
    @Published var scanProgress = 0.0
    @Published var isBusy = false
    @Published var isPrepared = false
    @Published var warningMessages: [String] = []
    @Published var finalOutputPath = ""

    private let runner = CommandRunner()
    private lazy var podspecService = PodspecService(
        runner: runner,
        podExecutable: podExecutable ?? ""
    )
    private lazy var packagingEngine = PackagingEngine(
        runner: runner,
        podExecutable: podExecutable ?? ""
    )
    private let podExecutable = ToolLocator.executable(named: "pod")
    private var remoteSpecs: [String: PodSpecRecord] = [:]
    private var supplementalSpecs: [String: PodSpecRecord] = [:]
    private var resolvedSpecs: [PodSpecRecord] = []
    private var preparedSession: PreparedBuildSession?

    var canScan: Bool {
        rootDirectoryPath.isEmpty == false && isBusy == false
    }

    var canPrepare: Bool {
        selectedRootSpec != nil &&
            resolutionRows.contains(where: {
                $0.state == .unresolved || $0.state == .versionConflict
            }) == false &&
            resolvedSpecs.isEmpty == false &&
            isBusy == false
    }

    var canPackage: Bool {
        isPrepared && preparedSession != nil && isBusy == false
    }

    var selectedRootSpec: PodSpecRecord? {
        localSpecs.first(where: { $0.name == selectedRootName })
    }

    var unresolvedCount: Int {
        resolutionRows.filter {
            $0.state == .unresolved || $0.state == .versionConflict
        }.count
    }

    var overallProgress: Double {
        if stage == .scanning {
            return scanProgress * 0.10
        };return stage.progress
    }

    // 弹出目录选择器，选择统一管理的本地 Pod 根目录。
    func chooseRootDirectory() {
        guard let url = chooseDirectory(
            title: "选择 JobsByPods 根目录",
            prompt: "导入并扫描"
        ) else { return }
        rootDirectoryPath = url.path
        Task {
            await scanLocalPods()
        }
    }

    // 接受 Finder 拖入的本地目录。
    func acceptDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }
        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            options: nil
        ) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else { return }
            Task { @MainActor [weak self] in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue else {
                    self?.presentError("只能拖入目录，不能拖入单个文件。")
                    return
                }
                self?.rootDirectoryPath = url.path
                await self?.scanLocalPods()
            }
        };return true
    }

    // 弹出目录选择器，设置最终二进制 SDK 的输出位置。
    func chooseOutputDirectory() {
        guard let url = chooseDirectory(
            title: "选择最终产物输出目录",
            prompt: "使用此目录"
        ) else { return }
        outputDirectoryPath = url.path
    }

    // 扫描全部本地 podspec，建立 Pod 名到唯一路径的索引。
    func scanLocalPods() async {
        guard canScan else { return }
        guard let podExecutable else {
            presentError(
                "没有找到 CocoaPods 的 pod 命令。\n请先安装 CocoaPods，再重新运行生成器。"
            )
            return
        }
        let rootURL = URL(fileURLWithPath: rootDirectoryPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            presentError("本地 Pod 根目录不存在：\(rootURL.path)")
            return
        }

        resetBuildState()
        isBusy = true
        stage = .scanning
        statusMessage = "正在用 CocoaPods 解析本地 podspec…"
        appendLog("使用 CocoaPods：\(podExecutable)\n")
        appendLog("扫描目录：\(rootURL.path)\n")

        do {
            let result = try await podspecService.scan(
                rootURL: rootURL,
                onProgress: { [weak self] current, total, name in
                    Task { @MainActor [weak self] in
                        self?.scanProgress = total == 0
                            ? 0
                            : Double(current) / Double(total)
                        self?.statusMessage = "解析 \(name)（\(current)/\(total)）"
                    }
                },
                onOutput: outputHandler
            )
            localSpecs = result.specs
            warningMessages = result.warnings
            selectedRootName = result.specs.first?.name ?? ""
            appendLog(
                "\n扫描完成：\(result.specs.count) 个唯一 Pod，\(result.warnings.count) 个警告。\n"
            )
            resolveDependencyGraph()
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 切换需要打包的主 Pod，并重新计算其传递依赖闭包。
    func selectRoot(_ podName: String) {
        guard isBusy == false else { return }
        selectedRootName = podName
        resetPreparedState()
        resolveDependencyGraph()
    }

    // 查询缺失依赖的 CocoaPods 元数据，待用户明确确认后才纳入来源图。
    func queryRemote(for row: DependencyResolutionRow) async {
        guard isBusy == false, row.state == .unresolved else { return }
        isBusy = true
        statusMessage = "正在 CocoaPods Specs 查询 \(row.dependency.rootName)…"
        do {
            let spec = try await podspecService.queryRemote(
                dependency: row.dependency,
                onOutput: outputHandler
            )
            if confirmRemoteSpec(spec, requestedBy: row.dependency.requestedBy) {
                remoteSpecs[spec.name] = spec
                appendLog(
                    "\n已确认远程 Pod：\(spec.name) \(spec.version)，许可证：\(spec.license)\n"
                )
                resolveDependencyGraph()
            } else {
                statusMessage = "已取消使用远程 \(spec.name)。"
            }
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 让用户为缺失依赖补充本地 Pod 目录，并校验 Pod 名和本地唯一性。
    func chooseLocal(for row: DependencyResolutionRow) async {
        guard isBusy == false else { return }
        guard let directoryURL = chooseDirectory(
            title: "选择 \(row.dependency.rootName) 所在的本地目录",
            prompt: "导入本地依赖"
        ) else { return }

        isBusy = true
        statusMessage = "正在解析补充的本地依赖…"
        do {
            let result = try await podspecService.scan(
                rootURL: directoryURL,
                sourceKindOverride: .localSupplement,
                onProgress: { _, _, _ in },
                onOutput: outputHandler
            )
            guard let spec = result.specs.first(where: {
                $0.name == row.dependency.rootName
            }) else {
                throw BuilderError.scan(
                    "所选目录没有名为 \(row.dependency.rootName) 的 podspec。"
                )
            }
            if let existing = localSpecs.first(where: { $0.name == spec.name }) {
                throw BuilderError.duplicatePod(
                    spec.name,
                    [existing.podspecPath, spec.podspecPath]
                )
            }
            supplementalSpecs[spec.name] = spec
            warningMessages.append(contentsOf: result.warnings)
            appendLog("\n已补充本地 Pod：\(spec.name) → \(spec.directoryPath)\n")
            resolveDependencyGraph()
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 生成真实 CocoaPods Workspace，并完成真机和模拟器预编译验证。
    func prepareBuild() async {
        guard canPrepare,
              let rootSpec = selectedRootSpec else {
            presentError("依赖闭包尚未完全解决，不能进入预编译。")
            return
        }
        isBusy = true
        resetPreparedState()
        statusMessage = "正在生成临时工程并预编译验证…"
        appendLog("\n========== 开始预编译验证 ==========\n")
        do {
            let session = try await packagingEngine.prepare(
                rootSpec: rootSpec,
                allSpecs: resolvedSpecs,
                onStage: stageHandler,
                onOutput: outputHandler
            )
            preparedSession = session
            provenanceRows = session.provenanceRows
            isPrepared = true
            stage = .awaitingConfirmation
            statusMessage = "预编译通过。请检查最终来源表，再确认正式打包。"
            appendLog("\n预编译验证通过，来源指纹已冻结。\n")
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 展示最终来源表，等待用户按 Enter 后才正式开始打包。
    func confirmAndPackage() async {
        guard canPackage,
              let session = preparedSession else { return }
        guard confirmProvenanceRows(provenanceRows) else {
            statusMessage = "用户取消正式打包；预编译结果仍然保留。"
            return
        }
        let outputURL = URL(
            fileURLWithPath: outputDirectoryPath,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: outputURL,
                withIntermediateDirectories: true
            )
        } catch {
            presentError("无法创建输出目录：\(error.localizedDescription)")
            return
        }

        isBusy = true
        appendLog("\n========== 用户已确认，开始正式打包 ==========\n")
        do {
            let outcome = try await packagingEngine.package(
                session: session,
                outputParentURL: outputURL,
                onStage: stageHandler,
                onOutput: outputHandler
            )
            finalOutputPath = outcome.outputURL.path
            try writeLog(to: outcome.outputURL)
            stage = .completed
            statusMessage = "完成：\(outcome.xcframeworkCount) 个 XCFramework，\(outcome.resourceBundleCount) 个资源 Bundle。"
            NSWorkspace.shared.activateFileViewerSelecting([outcome.outputURL])
            presentInformation(
                title: "打包完成",
                message: "\(statusMessage)\n\n产物：\(outcome.outputURL.path)"
            )
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 取消正在执行的 CocoaPods 或 Xcode 构建进程。
    func cancelCurrentTask() {
        packagingEngine.cancel()
        runner.cancel()
        stage = .cancelled
        statusMessage = "正在取消当前任务…"
    }

    // 根据本地最高优先级规则递归计算当前主 Pod 的依赖闭包。
    private func resolveDependencyGraph() {
        guard let rootSpec = selectedRootSpec else {
            resolutionRows = []
            resolvedSpecs = []
            stage = .idle
            return
        }

        stage = .resolving
        resetPreparedState()
        let localCatalog = Dictionary(
            uniqueKeysWithValues: (localSpecs + Array(supplementalSpecs.values)).map {
                ($0.name, $0)
            }
        )
        var catalog = remoteSpecs
        for (name, spec) in localCatalog {
            catalog[name] = spec
        }

        var queue = [rootSpec]
        var visited: Set<String> = []
        var graphSpecs: [String: PodSpecRecord] = [rootSpec.name: rootSpec]
        var rows: [DependencyResolutionRow] = []
        var seenDependencyRows: Set<String> = []

        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current.name).inserted else { continue }
            for dependency in current.dependencies {
                let normalized = PodDependency(
                    name: dependency.name,
                    requirement: dependency.requirement,
                    requestedBy: current.name
                )
                let rowKey = "\(normalized.requestedBy)|\(normalized.rootName)|\(normalized.requirement)"
                guard seenDependencyRows.insert(rowKey).inserted else { continue }

                if let spec = catalog[normalized.rootName] {
                    let matches = VersionRequirement.matches(
                        version: spec.version,
                        requirement: normalized.requirement
                    )
                    let state: DependencyResolutionState = matches
                        ? (spec.sourceKind.isLocal ? .resolvedLocal : .resolvedRemote)
                        : .versionConflict
                    let detail = matches
                        ? "\(spec.sourceKind.displayName) · \(spec.version) · \(displaySource(spec))"
                        : "\(current.name) 要求 \(normalized.requirement.isEmpty ? "未限定" : normalized.requirement)，当前 \(spec.version)"
                    rows.append(DependencyResolutionRow(
                        dependency: normalized,
                        state: state,
                        resolvedSpec: spec,
                        detail: detail
                    ))
                    if matches {
                        graphSpecs[spec.name] = spec
                        queue.append(spec)
                    }
                } else {
                    rows.append(DependencyResolutionRow(
                        dependency: normalized,
                        state: .unresolved,
                        resolvedSpec: nil,
                        detail: "本地索引中不存在；请选择网络查询或补充本地目录。"
                    ))
                }
            }
        }

        resolutionRows = rows.sorted {
            if $0.state != $1.state {
                return $0.state.rawValue < $1.state.rawValue
            };return $0.dependency.rootName < $1.dependency.rootName
        }
        resolvedSpecs = graphSpecs.values.sorted {
            if $0.name == rootSpec.name { return true }
            if $1.name == rootSpec.name { return false }
            return $0.name < $1.name
        }
        stage = .idle
        let dependencyCount = max(0, resolvedSpecs.count - 1)
        statusMessage = unresolvedCount == 0
            ? "依赖闭包已解决：主 Pod 1 个，传递依赖 \(dependencyCount) 个。"
            : "依赖闭包有 \(unresolvedCount) 项需要人工处理。"
    }

    // 清空与正式构建有关的状态，但保留本地 Pod 索引。
    private func resetBuildState() {
        localSpecs = []
        selectedRootName = ""
        resolutionRows = []
        remoteSpecs = [:]
        supplementalSpecs = [:]
        resolvedSpecs = []
        warningMessages = []
        finalOutputPath = ""
        scanProgress = 0
        resetPreparedState()
    }

    // 主 Pod 或依赖图变化后，废弃此前的预编译和来源确认。
    private func resetPreparedState() {
        if let preparedSession {
            packagingEngine.discard(session: preparedSession)
        }
        preparedSession = nil
        provenanceRows = []
        isPrepared = false
    }

    // 生成线程安全的命令输出回调。
    private var outputHandler: (String) -> Void {
        { [weak self] text in
            Task { @MainActor [weak self] in
                self?.appendLog(text)
            }
        }
    }

    // 生成线程安全的构建阶段回调。
    private var stageHandler: (BuildStage) -> Void {
        { [weak self] stage in
            Task { @MainActor [weak self] in
                self?.stage = stage
                self?.statusMessage = stage.title
            }
        }
    }

    // 把流式日志追加到界面，限制长期任务的内存占用。
    private func appendLog(_ text: String) {
        logText.append(text)
        let maximumCharacterCount = 500_000
        if logText.count > maximumCharacterCount {
            logText.removeFirst(logText.count - maximumCharacterCount)
        }
    }

    // 统一处理失败状态并展示可操作错误。
    private func fail(_ error: Error) {
        if case BuilderError.cancelled = error {
            stage = .cancelled
            statusMessage = BuilderError.cancelled.localizedDescription
            appendLog("\n任务已取消。\n")
            return
        }
        stage = .failed
        statusMessage = error.localizedDescription
        appendLog("\n错误：\(error.localizedDescription)\n")
        presentError(error.localizedDescription)
    }

    // 展示远程 Pod 元数据，让回车成为唯一的继续入口。
    private func confirmRemoteSpec(
        _ spec: PodSpecRecord,
        requestedBy: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "确认使用远程 Pod？"
        alert.informativeText = """
        名称：\(spec.name)
        版本：\(spec.version)
        来源：\(spec.sourceURL.isEmpty ? "CocoaPods Specs" : spec.sourceURL)
        依赖方：\(requestedBy)
        许可证：\(spec.license)

        按 Enter 使用远程版本；按 Esc 取消。
        """
        alert.addButton(withTitle: "使用远程版本")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    // 展示最终来源和打包方式，明确用户确认后的责任边界。
    private func confirmProvenanceRows(_ rows: [ProvenanceRow]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "最终来源表：确认后才开始正式打包"
        alert.informativeText = """
        下表是本次二进制产物的真实来源、版本、许可证和打包方式。
        工具已经完成双 SDK 预编译，并冻结当前来源指纹。

        按 Enter 确认来源并正式打包；按 Esc 取消。
        """
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 840, height: 320))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = provenanceText(rows)
        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = textView
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "确认并开始打包")
        alert.addButton(withTitle: "取消")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    // 把来源行转换为便于复制和核对的制表文本。
    private func provenanceText(_ rows: [ProvenanceRow]) -> String {
        let header = ["模块", "关系", "版本", "来源", "打包", "许可证", "校验"]
            .joined(separator: "\t")
        let body = rows.map {
            [
                $0.name,
                $0.relationship,
                $0.version,
                $0.sourceType,
                $0.packagingMode,
                $0.license,
                String($0.fingerprint.prefix(12))
            ].joined(separator: "\t")
        }.joined(separator: "\n")
        return header + "\n" + body
    }

    // 统一创建只选目录的系统面板。
    private func chooseDirectory(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    // 把完整运行日志写入最终产物目录。
    private func writeLog(to outputURL: URL) throws {
        let logsURL = outputURL.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true
        )
        try logText.write(
            to: logsURL.appendingPathComponent("JobsPodBinaryBuilder.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    // 返回界面展示所需的来源路径。
    private func displaySource(_ spec: PodSpecRecord) -> String {
        spec.sourceKind.isLocal
            ? spec.directoryPath
            : (spec.sourceURL.isEmpty ? "CocoaPods Specs" : spec.sourceURL)
    }

    // 展示阻断性错误。
    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "JobsPodBinaryBuilder"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    // 展示任务完成信息。
    private func presentInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "完成")
        alert.runModal()
    }
}
