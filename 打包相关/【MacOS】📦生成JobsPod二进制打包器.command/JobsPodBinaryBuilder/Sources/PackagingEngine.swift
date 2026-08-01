//
//  PackagingEngine.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import CryptoKit
import Foundation

struct PackageOutcome {
    let outputURL: URL
    let xcframeworkCount: Int
    let resourceBundleCount: Int
}

final class PackagingEngine {
    private let runner: CommandRunner
    private let podExecutable: String
    private let xcodebuildExecutable: String

    init(
        runner: CommandRunner,
        podExecutable: String,
        xcodebuildExecutable: String = "/usr/bin/xcodebuild"
    ) {
        self.runner = runner
        self.podExecutable = podExecutable
        self.xcodebuildExecutable = xcodebuildExecutable
    }

    // 生成临时工程，完成 pod install、工程检查及双 SDK 预编译。
    func prepare(
        rootSpec: PodSpecRecord,
        allSpecs: [PodSpecRecord],
        onStage: @escaping (BuildStage) -> Void,
        onOutput: @escaping (String) -> Void
    ) async throws -> PreparedBuildSession {
        let sessionURL = try createSessionDirectory(rootName: rootSpec.name)
        try ProjectGenerator.writePackagingWorkspace(
            at: sessionURL,
            rootSpec: rootSpec,
            allSpecs: allSpecs
        )

        onStage(.installing)
        try await runChecked(
            executable: podExecutable,
            arguments: ["install", "--no-repo-update", "--verbose", "--no-ansi"],
            currentDirectory: sessionURL,
            label: "pod install",
            onOutput: onOutput
        )

        let workspaceURL = sessionURL.appendingPathComponent("PackagingHost.xcworkspace")
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else {
            throw BuilderError.validation("pod install 没有生成 PackagingHost.xcworkspace。")
        }

        onStage(.validatingProject)
        let listResult = try await runChecked(
            executable: xcodebuildExecutable,
            arguments: ["-workspace", workspaceURL.path, "-list"],
            currentDirectory: sessionURL,
            label: "xcodebuild -list",
            onOutput: onOutput
        )
        guard listResult.output.contains("PackagingHost") else {
            throw BuilderError.validation("生成的 Workspace 中没有 PackagingHost Scheme。")
        }
        let podsProjectURL = sessionURL
            .appendingPathComponent("Pods")
            .appendingPathComponent("Pods.xcodeproj")
        guard FileManager.default.fileExists(atPath: podsProjectURL.path) else {
            throw BuilderError.validation("Pods.xcodeproj 不存在，CocoaPods 工程生成不完整。")
        }

        onStage(.prebuildingDevice)
        let preflightDeviceURL = sessionURL.appendingPathComponent("DerivedData/PreflightDevice")
        try await buildHost(
            workspaceURL: workspaceURL,
            sdk: "iphoneos",
            destination: "generic/platform=iOS",
            derivedDataURL: preflightDeviceURL,
            clean: true,
            onOutput: onOutput
        )

        onStage(.prebuildingSimulator)
        let preflightSimulatorURL = sessionURL.appendingPathComponent("DerivedData/PreflightSimulator")
        try await buildHost(
            workspaceURL: workspaceURL,
            sdk: "iphonesimulator",
            destination: "generic/platform=iOS Simulator",
            derivedDataURL: preflightSimulatorURL,
            clean: true,
            onOutput: onOutput
        )

        guard findFramework(
            moduleName: rootSpec.moduleName,
            podName: rootSpec.name,
            within: preflightDeviceURL,
            sdkMarker: "Release-iphoneos"
        ) != nil else {
            throw BuilderError.validation(
                "预编译通过，但没有找到 \(rootSpec.moduleName).framework；该 Pod 可能不是可直接二进制化的 Framework Target。"
            )
        }

        let provenanceRows = try makeProvenanceRows(
            rootSpec: rootSpec,
            allSpecs: allSpecs
        )
        let fingerprint = combinedFingerprint(provenanceRows)
        return PreparedBuildSession(
            rootSpec: rootSpec,
            allSpecs: allSpecs,
            workspaceURL: workspaceURL,
            sessionURL: sessionURL,
            provenanceRows: provenanceRows,
            sourceFingerprint: fingerprint
        )
    }

    // 在用户确认来源表后正式构建、组装并验证二进制 SDK。
    func package(
        session: PreparedBuildSession,
        outputParentURL: URL,
        onStage: @escaping (BuildStage) -> Void,
        onOutput: @escaping (String) -> Void
    ) async throws -> PackageOutcome {
        let currentRows = try makeProvenanceRows(
            rootSpec: session.rootSpec,
            allSpecs: session.allSpecs
        )
        guard combinedFingerprint(currentRows) == session.sourceFingerprint else {
            throw BuilderError.validation(
                "来源确认后检测到本地源码或 podspec 已变化，必须重新预编译并确认来源表。"
            )
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let outputURL = outputParentURL.appendingPathComponent(
            "\(session.rootSpec.name)-BinarySDK-\(timestamp)",
            isDirectory: true
        )
        let dependenciesURL = outputURL.appendingPathComponent("Dependencies", isDirectory: true)
        let resourcesURL = outputURL.appendingPathComponent("Resources", isDirectory: true)
        let logsURL = outputURL.appendingPathComponent("Logs", isDirectory: true)
        for directory in [outputURL, dependenciesURL, resourcesURL, logsURL] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        onStage(.buildingDevice)
        let deviceDataURL = session.sessionURL.appendingPathComponent("DerivedData/PackageDevice")
        try await buildHost(
            workspaceURL: session.workspaceURL,
            sdk: "iphoneos",
            destination: "generic/platform=iOS",
            derivedDataURL: deviceDataURL,
            clean: true,
            onOutput: onOutput
        )

        onStage(.buildingSimulator)
        let simulatorDataURL = session.sessionURL.appendingPathComponent("DerivedData/PackageSimulator")
        try await buildHost(
            workspaceURL: session.workspaceURL,
            sdk: "iphonesimulator",
            destination: "generic/platform=iOS Simulator",
            derivedDataURL: simulatorDataURL,
            clean: true,
            onOutput: onOutput
        )

        onStage(.assembling)
        var frameworkRelativePaths: [String] = []
        var xcframeworkCount = 0
        for spec in session.allSpecs.sorted(by: { $0.name < $1.name }) {
            guard let deviceFramework = findFramework(
                moduleName: spec.moduleName,
                podName: spec.name,
                within: deviceDataURL,
                sdkMarker: "Release-iphoneos"
            ), let simulatorFramework = findFramework(
                moduleName: spec.moduleName,
                podName: spec.name,
                within: simulatorDataURL,
                sdkMarker: "Release-iphonesimulator"
            ) else {
                throw BuilderError.validation(
                    "没有找到 \(spec.name) 的真机或模拟器 Framework 产物。"
                )
            }

            let isRoot = spec.name == session.rootSpec.name
            let relativePath = isRoot
                ? "\(spec.moduleName).xcframework"
                : "Dependencies/\(spec.moduleName).xcframework"
            let destinationURL = outputURL.appendingPathComponent(relativePath)
            try await runChecked(
                executable: xcodebuildExecutable,
                arguments: [
                    "-create-xcframework",
                    "-framework", deviceFramework.path,
                    "-framework", simulatorFramework.path,
                    "-output", destinationURL.path
                ],
                currentDirectory: session.sessionURL,
                label: "xcodebuild -create-xcframework \(spec.name)",
                onOutput: onOutput
            )
            frameworkRelativePaths.append(relativePath)
            xcframeworkCount += 1
        }

        let resourceBundleCount = try copyResourceBundles(
            from: deviceDataURL,
            to: resourcesURL
        )
        let dependencySpecs = session.allSpecs.filter { $0.name != session.rootSpec.name }
        let binaryPodspec = ProjectGenerator.binaryPodspec(
            rootSpec: session.rootSpec,
            dependencySpecs: dependencySpecs,
            frameworkRelativePaths: frameworkRelativePaths,
            hasResources: resourceBundleCount > 0
        )
        try binaryPodspec.write(
            to: outputURL.appendingPathComponent("\(session.rootSpec.name).podspec"),
            atomically: true,
            encoding: .utf8
        )
        try writeReports(
            rows: currentRows,
            rootSpec: session.rootSpec,
            outputURL: outputURL
        )
        let sourceLockURL = session.sessionURL.appendingPathComponent("Podfile.lock")
        if FileManager.default.fileExists(atPath: sourceLockURL.path) {
            try FileManager.default.copyItem(
                at: sourceLockURL,
                to: outputURL.appendingPathComponent("Podfile.lock")
            )
        }

        onStage(.validatingConsumer)
        try await validateConsumer(
            rootSpec: session.rootSpec,
            binarySDKURL: outputURL,
            onOutput: onOutput
        )

        return PackageOutcome(
            outputURL: outputURL,
            xcframeworkCount: xcframeworkCount,
            resourceBundleCount: resourceBundleCount
        )
    }

    // 请求终止当前外部构建进程。
    func cancel() {
        runner.cancel()
    }

    // 丢弃已经失效的受控缓存会话，避免切换主 Pod 后持续占用磁盘。
    func discard(session: PreparedBuildSession) {
        let sessionsRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "JobsPodBinaryBuilder/Sessions",
            isDirectory: true
        ).standardizedFileURL
        let sessionURL = session.sessionURL.standardizedFileURL
        let allowedPrefix = sessionsRoot.path + "/"
        guard sessionURL.path.hasPrefix(allowedPrefix),
              sessionURL.path != sessionsRoot.path else {
            return
        }
        try? FileManager.default.removeItem(at: sessionURL)
    }

    // 运行 iOS 宿主 Scheme，从而同时构建依赖闭包中的全部 Pod Target。
    private func buildHost(
        workspaceURL: URL,
        sdk: String,
        destination: String,
        derivedDataURL: URL,
        clean: Bool,
        onOutput: @escaping (String) -> Void
    ) async throws {
        var arguments = [
            "-workspace", workspaceURL.path,
            "-scheme", "PackagingHost",
            "-configuration", "Release",
            "-sdk", sdk,
            "-destination", destination,
            "-derivedDataPath", derivedDataURL.path,
            "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
            "SKIP_INSTALL=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO"
        ]
        if clean {
            arguments.append("clean")
        }
        arguments.append("build")
        try await runChecked(
            executable: xcodebuildExecutable,
            arguments: arguments,
            currentDirectory: workspaceURL.deletingLastPathComponent(),
            label: "xcodebuild \(sdk)",
            onOutput: onOutput
        )
    }

    // 构建二进制消费 Demo，验证模块导入、链接和资源集成。
    private func validateConsumer(
        rootSpec: PodSpecRecord,
        binarySDKURL: URL,
        onOutput: @escaping (String) -> Void
    ) async throws {
        let consumerURL = binarySDKURL.appendingPathComponent("ConsumerDemo", isDirectory: true)
        try ProjectGenerator.writeConsumerDemo(
            at: consumerURL,
            rootSpec: rootSpec,
            binarySDKURL: binarySDKURL
        )
        try await runChecked(
            executable: podExecutable,
            arguments: ["install", "--no-repo-update", "--no-ansi"],
            currentDirectory: consumerURL,
            label: "ConsumerDemo pod install",
            onOutput: onOutput
        )
        let workspaceURL = consumerURL.appendingPathComponent("ConsumerDemo.xcworkspace")
        try await runChecked(
            executable: xcodebuildExecutable,
            arguments: [
                "-workspace", workspaceURL.path,
                "-scheme", "ConsumerDemo",
                "-configuration", "Release",
                "-sdk", "iphonesimulator",
                "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", consumerURL.appendingPathComponent("DerivedData").path,
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "clean",
                "build"
            ],
            currentDirectory: consumerURL,
            label: "ConsumerDemo xcodebuild",
            onOutput: onOutput
        )
    }

    // 执行命令并把非零退出码统一转换为可展示错误。
    @discardableResult
    private func runChecked(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        label: String,
        onOutput: @escaping (String) -> Void
    ) async throws -> CommandResult {
        onOutput("\n▶ \(label)\n")
        let result = try await runner.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            onOutput: onOutput
        )
        guard result.exitCode == 0 else {
            throw BuilderError.command(
                ([executable] + arguments).joined(separator: " "),
                result.exitCode,
                result.output
            )
        };return result
    }

    // 在 DerivedData 中定位指定 Pod 的 Framework 产品。
    private func findFramework(
        moduleName: String,
        podName: String,
        within derivedDataURL: URL,
        sdkMarker: String
    ) -> URL? {
        let productsURL = derivedDataURL.appendingPathComponent("Build/Products")
        guard let enumerator = FileManager.default.enumerator(
            at: productsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return nil
        }
        let expectedNames = [
            "\(moduleName).framework",
            "\(podName).framework",
            "\(podName.replacingOccurrences(of: "-", with: "_")).framework"
        ]
        for case let url as URL in enumerator {
            guard url.path.contains(sdkMarker),
                  expectedNames.contains(url.lastPathComponent) else {
                continue
            }
            enumerator.skipDescendants()
            return url
        };return nil
    }

    // 收集 Release-iphoneos 中生成的资源 Bundle。
    private func copyResourceBundles(from deviceDataURL: URL, to destinationURL: URL) throws -> Int {
        let productsURL = deviceDataURL.appendingPathComponent("Build/Products")
        guard let enumerator = FileManager.default.enumerator(
            at: productsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        var copiedNames: Set<String> = []
        for case let url as URL in enumerator {
            guard url.path.contains("Release-iphoneos"),
                  url.pathExtension == "bundle",
                  copiedNames.contains(url.lastPathComponent) == false else {
                continue
            }
            let destination = destinationURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            copiedNames.insert(url.lastPathComponent)
            enumerator.skipDescendants()
        };return copiedNames.count
    }

    // 建立 Pod、系统 Framework 与系统 Library 的最终来源表。
    private func makeProvenanceRows(
        rootSpec: PodSpecRecord,
        allSpecs: [PodSpecRecord]
    ) throws -> [ProvenanceRow] {
        var rows: [ProvenanceRow] = []
        for spec in allSpecs.sorted(by: { $0.name < $1.name }) {
            let isRoot = spec.name == rootSpec.name
            let sourceIdentity: String
            if spec.sourceKind.isLocal {
                sourceIdentity = spec.directoryPath
            } else {
                sourceIdentity = spec.sourceURL.isEmpty
                    ? "CocoaPods Specs"
                    : spec.sourceURL
            }
            let fingerprint = try SourceFingerprint.forSpec(spec)
            rows.append(ProvenanceRow(
                name: spec.name,
                relationship: isRoot ? "主 Pod" : "传递依赖",
                version: spec.version,
                sourceType: spec.sourceKind.displayName,
                sourceIdentity: sourceIdentity,
                packagingMode: isRoot ? "主 XCFramework" : "依赖 XCFramework",
                license: spec.license,
                verification: "预编译通过",
                fingerprint: fingerprint
            ))
        }

        let frameworks = Array(Set(allSpecs.flatMap(\.frameworks))).sorted()
        rows.append(contentsOf: frameworks.map {
            ProvenanceRow(
                name: $0,
                relationship: "系统依赖",
                version: "当前 SDK",
                sourceType: "Apple SDK",
                sourceIdentity: "当前 Xcode SDK",
                packagingMode: "外部链接",
                license: "系统",
                verification: "由 Xcode 链接验证",
                fingerprint: "system-framework:\($0)"
            )
        })
        let libraries = Array(Set(allSpecs.flatMap(\.libraries))).sorted()
        rows.append(contentsOf: libraries.map {
            ProvenanceRow(
                name: $0,
                relationship: "系统依赖",
                version: "当前 SDK",
                sourceType: "Apple Library",
                sourceIdentity: "当前 Xcode SDK",
                packagingMode: "外部链接",
                license: "系统",
                verification: "由 Xcode 链接验证",
                fingerprint: "system-library:\($0)"
            )
        });return rows
    }

    // 将来源表指纹合并为最终确认门禁值。
    private func combinedFingerprint(_ rows: [ProvenanceRow]) -> String {
        let source = rows
            .sorted(by: { $0.id < $1.id })
            .map { "\($0.id)|\($0.fingerprint)" }
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // 把来源表输出为 JSON、HTML 和第三方告知文档。
    private func writeReports(
        rows: [ProvenanceRow],
        rootSpec: PodSpecRecord,
        outputURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(rows)
        try jsonData.write(to: outputURL.appendingPathComponent("DependencyProvenance.json"))

        let htmlRows = rows.map { row in
            """
            <tr>
              <td>\(htmlEscape(row.name))</td>
              <td>\(htmlEscape(row.relationship))</td>
              <td>\(htmlEscape(row.version))</td>
              <td>\(htmlEscape(row.sourceType))</td>
              <td>\(htmlEscape(publicSourceIdentity(row)))</td>
              <td>\(htmlEscape(row.packagingMode))</td>
              <td>\(htmlEscape(row.license))</td>
              <td>\(htmlEscape(row.verification))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>\(htmlEscape(rootSpec.name)) 二进制来源报告</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; color: #1f2937; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; vertical-align: top; }
            th { background: #f3f4f6; }
            h1 { margin-bottom: 8px; }
            p { color: #4b5563; }
          </style>
        </head>
        <body>
          <h1>\(htmlEscape(rootSpec.name)) 二进制来源报告</h1>
          <p>该报告由 JobsPodBinaryBuilder 根据用户确认并冻结的依赖图生成。</p>
          <table>
            <thead>
              <tr><th>模块</th><th>关系</th><th>版本</th><th>来源类型</th><th>来源</th><th>打包方式</th><th>许可证</th><th>验证</th></tr>
            </thead>
            <tbody>
              \(htmlRows)
            </tbody>
          </table>
        </body>
        </html>
        """
        try html.write(
            to: outputURL.appendingPathComponent("DependencyProvenance.html"),
            atomically: true,
            encoding: .utf8
        )

        let thirdPartyRows = rows.filter {
            $0.sourceType == PodSourceKind.localManual.displayName ||
                $0.sourceType == PodSourceKind.remote.displayName
        }
        let notices = thirdPartyRows.isEmpty
            ? "# 第三方依赖告知\n\n本次产物未识别到第三方 Pod。\n"
            : "# 第三方依赖告知\n\n" + thirdPartyRows.map {
                "- \($0.name) \($0.version)：\($0.license)，来源：\(publicSourceIdentity($0))"
            }.joined(separator: "\n") + "\n"
        try notices.write(
            to: outputURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    // 创建每次任务独立的缓存目录。
    private func createSessionDirectory(rootName: String) throws -> URL {
        let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("JobsPodBinaryBuilder/Sessions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        let sessionURL = cacheRoot.appendingPathComponent(
            "\(rootName)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sessionURL,
            withIntermediateDirectories: true
        );return sessionURL
    }

    // 对外报告隐藏本机绝对路径，只保留目录身份和源码指纹。
    private func publicSourceIdentity(_ row: ProvenanceRow) -> String {
        guard row.sourceIdentity.hasPrefix("/") else { return row.sourceIdentity }
        return "\(URL(fileURLWithPath: row.sourceIdentity).lastPathComponent) / \(row.fingerprint.prefix(12))"
    }

    // 转义 HTML 单元格内容。
    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

enum SourceFingerprint {
    // 为本地目录或远程 podspec 计算稳定 SHA-256 指纹。
    static func forSpec(_ spec: PodSpecRecord) throws -> String {
        if spec.sourceKind == .remote {
            let data = try Data(contentsOf: URL(fileURLWithPath: spec.podspecPath))
            return sha256(data)
        }
        return try directoryFingerprint(URL(fileURLWithPath: spec.directoryPath))
    }

    // 递归哈希源码目录，跳过 Git、Pods 和构建产物。
    private static func directoryFingerprint(_ directoryURL: URL) throws -> String {
        let excluded: Set<String> = [
            ".git", ".build", "pods", "build", "deriveddata", "archive", "archives", "output", "outputs"
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw BuilderError.validation("无法为目录计算来源指纹：\(directoryURL.path)")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                if excluded.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values?.isRegularFile == true {
                files.append(url)
            }
        }

        var hasher = SHA256()
        for fileURL in files.sorted(by: { $0.path < $1.path }) {
            let relativePath = fileURL.path.replacingOccurrences(
                of: directoryURL.path + "/",
                with: ""
            )
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: try Data(contentsOf: fileURL, options: [.mappedIfSafe]))
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // 计算单段数据的 SHA-256。
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
