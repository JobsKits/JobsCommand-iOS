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
    @Published var cocoaPodsDirectoryPath = ""
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
    @Published private(set) var visibleLogText = ""
    @Published var scanProgress = 0.0
    @Published var isBusy = false
    @Published var isPrepared = false
    @Published var warningMessages: [String] = []
    @Published var finalOutputPath = ""
    @Published var cocoaPodsSpecCount = 0
    @Published private(set) var attentionRootNames: Set<String> = []

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
    private var cocoaPodsSpecs: [String: PodSpecRecord] = [:]
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

    var canStartPackaging: Bool {
        canPrepare
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

    // 一次性导入原 Xcode 工程由 pod install 生成的完整 Pods 目录。
    func chooseCocoaPodsDirectory() {
        guard isBusy == false,
              let url = chooseDirectory(
                title: "选择 Xcode 工程中的 Pods 目录",
                prompt: "导入项目 Pods"
              ) else { return }
        Task {
            await importCocoaPodsDirectory(url)
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

    // 在 Finder 中直接打开界面所展示的目录路径。
    func openDirectory(_ path: String) {
        guard path.isEmpty == false else { return }
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            presentError("目录不存在：\(directoryURL.path)")
            return
        }
        guard NSWorkspace.shared.open(directoryURL) else {
            presentError("无法在 Finder 中打开：\(directoryURL.path)")
            return
        }
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
        defer { finishBusyOperation() }
        stage = .scanning
        statusMessage = "正在解析 JobsByPods 本地 podspec…"
        appendLog("使用 CocoaPods：\(podExecutable)\n")
        appendLog("扫描目录：\(rootURL.path)\n")

        do {
            let service = podspecService
            let progressHandler: (Int, Int, String) -> Void = { [weak self] current, total, name in
                Task { @MainActor [weak self] in
                    self?.scanProgress = total == 0
                        ? 0
                        : Double(current) / Double(total) * 0.80
                    self?.statusMessage = "解析 JobsByPods：\(name)（\(current)/\(total)）"
                }
            }
            let onOutput = outputHandler
            let result = try await Task.detached(priority: .userInitiated) {
                try await service.scan(
                    rootURL: rootURL,
                    onProgress: progressHandler,
                    onOutput: onOutput
                )
            }.value
            localSpecs = result.specs
            warningMessages = result.warnings
            selectedRootName = result.specs.first?.name ?? ""
            appendLog(
                "\n扫描完成：\(result.specs.count) 个唯一 Pod，\(result.warnings.count) 个警告。\n"
            )
            if let detectedPodsURL = podspecService.detectCocoaPodsDirectory(near: rootURL) {
                do {
                    try await loadCocoaPodsSnapshot(detectedPodsURL)
                } catch {
                    let message = "自动导入项目 Pods 失败：\(error.localizedDescription)"
                    warningMessages.append(message)
                    appendLog("\n警告：\(message)\n")
                }
            } else {
                appendLog(
                    "\n未在 JobsByPods 附近检测到 Pods/Manifest.lock；" +
                    "可通过左侧“导入项目 Pods”一次性补充。\n"
                )
            }
            await resolveMissingSpecsAutomatically(for: result.specs)
            updateAttentionRootNames()
            resolveDependencyGraph()
        } catch {
            fail(error)
        }
    }

    // 切换需要打包的主 Pod，并重新计算其传递依赖闭包。
    func selectRoot(_ podName: String) {
        guard isBusy == false else { return }
        selectedRootName = podName
        resetPreparedState()
        resolveDependencyGraph()
    }

    // 重跑项目 Pods、缓存和 Specs 自动解析；全部未命中后才保留人工入口。
    func retryAutomaticResolution(for row: DependencyResolutionRow) async {
        guard isBusy == false, row.state == .unresolved else { return }
        isBusy = true
        defer { finishBusyOperation() }
        stage = .resolving
        statusMessage = "正在自动解析 \(row.dependency.rootName)…"
        guard let rootSpec = selectedRootSpec else { return }
        await resolveMissingSpecsAutomatically(for: [rootSpec])
        updateAttentionRootNames()
        resolveDependencyGraph()
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
            updateAttentionRootNames()
            resolveDependencyGraph()
        } catch {
            fail(error)
        }
        isBusy = false
    }

    // 载入用户指定的完整项目 Pods，并立即重新计算当前依赖闭包。
    private func importCocoaPodsDirectory(_ directoryURL: URL) async {
        guard isBusy == false else { return }
        isBusy = true
        defer { finishBusyOperation() }
        resetPreparedState()
        stage = .scanning
        statusMessage = "正在导入项目 Pods、锁文件与 CocoaPods 缓存…"
        do {
            try await loadCocoaPodsSnapshot(directoryURL)
            resolveDependencyGraph()
        } catch {
            fail(error)
        }
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

    // 从唯一醒目的主入口串联预编译、来源确认和正式打包。
    func startFormalPackaging() async {
        guard canStartPackaging else { return }
        if isPrepared == false {
            await prepareBuild()
        }
        guard canPackage else { return }
        await confirmAndPackage()
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
            presentPackagingSuccess(
                outputURL: outcome.outputURL,
                summary: statusMessage
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
        let catalog = sourceCatalog()

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
                        detail: "项目 Pods、CocoaPods 下载缓存和本机 Specs 均未自动命中；请先重新导入完整 Pods，仍失败再人工介入。"
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
            if $1.name == rootSpec.name { return false };return $0.name < $1.name
        }
        stage = .idle
        let dependencyCount = max(0, resolvedSpecs.count - 1)
        statusMessage = unresolvedCount == 0
            ? "依赖闭包已自动解决：主 Pod 1 个，传递依赖 \(dependencyCount) 个。"
            : "自动解析完成，仍有 \(unresolvedCount) 项冲突或缺失需要人工介入。"
    }

    // 清空与正式构建有关的状态，但保留本地 Pod 索引。
    private func resetBuildState() {
        localSpecs = []
        selectedRootName = ""
        resolutionRows = []
        remoteSpecs = [:]
        cocoaPodsSpecs = [:]
        supplementalSpecs = [:]
        resolvedSpecs = []
        warningMessages = []
        finalOutputPath = ""
        cocoaPodsDirectoryPath = ""
        cocoaPodsSpecCount = 0
        attentionRootNames = []
        scanProgress = 0
        resetPreparedState()
    }

    // 把项目 Pods 锁快照装入自动来源目录，并保留可见进度和警告。
    private func loadCocoaPodsSnapshot(_ directoryURL: URL) async throws {
        let service = podspecService
        let progressHandler: (Int, Int, String) -> Void = { [weak self] current, total, name in
            guard current == 1 || current == total || current.isMultiple(of: 10) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.scanProgress = total == 0
                    ? 0.80
                    : 0.80 + Double(current) / Double(total) * 0.20
                self?.statusMessage = "导入项目 Pods：\(name)（\(current)/\(total)）"
            }
        }
        let result = try await Task.detached(priority: .userInitiated) {
            try service.scanCocoaPodsSnapshot(
                podsDirectoryURL: directoryURL,
                onProgress: progressHandler
            )
        }.value
        cocoaPodsDirectoryPath = result.podsDirectoryURL.path
        cocoaPodsSpecCount = result.installedPodCount
        cocoaPodsSpecs = Dictionary(uniqueKeysWithValues: result.specs.map {
            ($0.name, $0)
        })
        warningMessages.append(contentsOf: result.warnings)
        appendLog(
            "\n已自动导入项目 Pods：\(result.podsDirectoryURL.path)\n" +
            "锁文件：\(result.lockfileURL.path)\n" +
            "外源索引：\(result.specs.count) 个，警告：\(result.warnings.count) 个。\n"
        )
    }

    // 汇总来源优先级，供当前依赖图和左侧全量异常标记共用。
    private func sourceCatalog() -> [String: PodSpecRecord] {
        let localCatalog = Dictionary(
            uniqueKeysWithValues: (localSpecs + Array(supplementalSpecs.values)).map {
                ($0.name, $0)
            }
        )
        var catalog = remoteSpecs
        for (name, spec) in cocoaPodsSpecs {
            catalog[name] = spec
        }
        for (name, spec) in localCatalog {
            catalog[name] = spec
        };return catalog
    }

    // 为所有主 Pod 预计算是否仍存在缺失或版本冲突，驱动左侧红色感叹号。
    private func updateAttentionRootNames() {
        let catalog = sourceCatalog()
        attentionRootNames = Set(localSpecs.compactMap { rootSpec in
            dependencyGraphNeedsAttention(rootSpec, catalog: catalog)
                ? rootSpec.name
                : nil
        })
    }

    // 在后台递归查询所有尚未进入目录的 CocoaPods Specs，直到依赖闭包稳定。
    private func resolveMissingSpecsAutomatically(for rootSpecs: [PodSpecRecord]) async {
        let service = podspecService
        let onOutput = outputHandler
        var attemptedRootNames: Set<String> = []
        while true {
            let dependencies = missingDependencies(
                in: rootSpecs,
                catalog: sourceCatalog()
            ).filter {
                attemptedRootNames.contains($0.rootName) == false
            }
            guard dependencies.isEmpty == false else { break }
            for dependency in dependencies {
                attemptedRootNames.insert(dependency.rootName)
                stage = .resolving
                statusMessage = "后台自动解析 Specs：\(dependency.rootName)…"
                do {
                    let spec = try await Task.detached(priority: .userInitiated) {
                        try await service.queryRemote(
                            dependency: dependency,
                            onOutput: onOutput
                        )
                    }.value
                    remoteSpecs[spec.name] = spec
                    appendLog(
                        "\n已由本机 CocoaPods Specs 自动解析：" +
                        "\(spec.name) \(spec.version)，许可证：\(spec.license)\n"
                    )
                } catch {
                    let message = "\(dependency.rootName) 自动解析失败：\(error.localizedDescription)"
                    if warningMessages.contains(message) == false {
                        warningMessages.append(message)
                    }
                    appendLog("\n警告：\(message)\n")
                }
            }
        }
    }

    // 收集给定根 Pod 集合中尚无来源记录的唯一依赖，版本冲突保留给人工仲裁。
    private func missingDependencies(
        in rootSpecs: [PodSpecRecord],
        catalog: [String: PodSpecRecord]
    ) -> [PodDependency] {
        var queue = rootSpecs
        var visited: Set<String> = []
        var missingByRootName: [String: PodDependency] = [:]
        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current.name).inserted else { continue }
            for dependency in current.dependencies {
                if let spec = catalog[dependency.rootName] {
                    if VersionRequirement.matches(
                        version: spec.version,
                        requirement: dependency.requirement
                    ) {
                        queue.append(spec)
                    }
                } else if missingByRootName[dependency.rootName] == nil {
                    missingByRootName[dependency.rootName] = dependency
                }
            }
        };return missingByRootName.values.sorted {
            $0.rootName.localizedCaseInsensitiveCompare($1.rootName) == .orderedAscending
        }
    }

    // 在不改变当前选中项的前提下检查一个 Pod 的完整传递依赖。
    private func dependencyGraphNeedsAttention(
        _ rootSpec: PodSpecRecord,
        catalog: [String: PodSpecRecord]
    ) -> Bool {
        var queue = [rootSpec]
        var visited: Set<String> = []
        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current.name).inserted else { continue }
            for dependency in current.dependencies {
                guard let spec = catalog[dependency.rootName],
                      VersionRequirement.matches(
                        version: spec.version,
                        requirement: dependency.requirement
                      ) else {
                    return true
                }
                queue.append(spec)
            }
        };return false
    }

    // 结束扫描或解析后同时复位业务忙碌态和系统箭头光标。
    private func finishBusyOperation() {
        isBusy = false
        NSCursor.arrow.set()
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

    // 保留较完整的任务日志，界面仅渲染尾部以避免文本布局占满主线程。
    private func appendLog(_ text: String) {
        logText.append(text)
        let maximumCharacterCount = 500_000
        if logText.count > maximumCharacterCount {
            logText.removeFirst(logText.count - maximumCharacterCount)
        }
        let maximumVisibleCharacterCount = 16_000
        visibleLogText = logText.count > maximumVisibleCharacterCount
            ? "…已折叠较早日志，此处显示最新内容…\n" + String(
                logText.suffix(maximumVisibleCharacterCount)
            )
            : logText
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
        statusMessage = conciseStatusMessage(for: error)
        appendLog("\n错误：\(error.localizedDescription)\n")
        presentError(error.localizedDescription)
    }

    // 状态卡只承载失败摘要，不让命令堆栈参与 SwiftUI 布局。
    private func conciseStatusMessage(for error: Error) -> String {
        if case BuilderError.command(let command, let exitCode, _) = error {
            return "命令执行失败（\(exitCode)）：\(command)"
        }
        let message = error.localizedDescription
            .split(whereSeparator: \.isNewline)
            .prefix(3)
            .joined(separator: " ")
        let maximumCharacterCount = 500
        guard message.count > maximumCharacterCount else { return message };return String(
            message.prefix(maximumCharacterCount)
        ) + "…"
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
        let summary = message
            .split(whereSeparator: \.isNewline)
            .prefix(4)
            .joined(separator: "\n")
        alert.informativeText = summary.count > 700
            ? String(summary.prefix(700)) + "…"
            : summary
        if message.count > 700 {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 280))
            textView.isEditable = false
            textView.isSelectable = true
            textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.string = message
            let scrollView = NSScrollView(frame: textView.frame)
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.documentView = textView
            alert.accessoryView = scrollView
        }
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    // 打包完成后询问用户是否在 Finder 中打开产物目录。
    private func presentPackagingSuccess(outputURL: URL, summary: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "打包成功"
        alert.informativeText = """
        \(summary)

        产物：\(outputURL.path)

        是否现在打开这个打包文件夹？
        """
        alert.addButton(withTitle: "打开产物文件夹")
        alert.addButton(withTitle: "暂不打开")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn {
            openDirectory(outputURL.path)
        }
    }
}
