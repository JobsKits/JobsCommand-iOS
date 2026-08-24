//
//  PodspecService.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import CryptoKit
import Foundation

struct PodspecScanResult {
    let specs: [PodSpecRecord]
    let warnings: [String]
}

struct CocoaPodsSnapshotResult {
    let podsDirectoryURL: URL
    let lockfileURL: URL
    let specs: [PodSpecRecord]
    let warnings: [String]
    let installedPodCount: Int
}

final class PodspecService: @unchecked Sendable {
    private let runner: CommandRunner
    private let podExecutable: String
    private let excludedDirectoryNames: Set<String> = [
        ".git",
        ".build",
        "pods",
        "build",
        "deriveddata",
        "archive",
        "archives",
        "backup",
        "example",
        "examples",
        "demo",
        "demos",
        "test",
        "tests",
        "output",
        "outputs"
    ]

    init(runner: CommandRunner, podExecutable: String) {
        self.runner = runner
        self.podExecutable = podExecutable
    }

    // 扫描导入目录中的全部有效 podspec，并建立唯一 Pod 名索引。
    func scan(
        rootURL: URL,
        sourceKindOverride: PodSourceKind? = nil,
        onProgress: @escaping (Int, Int, String) -> Void,
        onOutput: @escaping (String) -> Void
    ) async throws -> PodspecScanResult {
        let podspecURLs = try collectPodspecURLs(rootURL: rootURL)
        guard podspecURLs.isEmpty == false else {
            throw BuilderError.scan("目录中没有找到有效的 *.podspec：\(rootURL.path)")
        }

        var parsedSpecs: [PodSpecRecord] = []
        var warnings: [String] = []
        for (index, podspecURL) in podspecURLs.enumerated() {
            onProgress(index + 1, podspecURLs.count, podspecURL.lastPathComponent)
            do {
                let spec = try await parsePodspec(
                    at: podspecURL,
                    sourceKindOverride: sourceKindOverride,
                    onOutput: onOutput
                )
                parsedSpecs.append(spec)
            } catch {
                warnings.append("\(podspecURL.path)：\(error.localizedDescription)")
            }
        }

        let grouped = Dictionary(grouping: parsedSpecs, by: \.name)
        if let duplicate = grouped.first(where: { $0.value.count > 1 }) {
            throw BuilderError.duplicatePod(
                duplicate.key,
                duplicate.value.map(\.podspecPath).sorted()
            )
        }
        guard parsedSpecs.isEmpty == false else {
            let failureSamples = warnings.prefix(3).map { warning in
                guard warning.count > 700 else { return warning };return String(warning.prefix(700)) + "…"
            }.joined(separator: "\n\n")
            let remainingCount = max(0, warnings.count - 3)
            let remainingMessage = remainingCount == 0
                ? ""
                : "\n\n另有 \(remainingCount) 份 podspec 解析失败，完整信息见实时日志。"
            throw BuilderError.scan(
                "发现了 podspec，但没有任何文件可以被 CocoaPods 正确解析。\n\n" +
                failureSamples + remainingMessage
            )
        };return PodspecScanResult(
            specs: parsedSpecs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            warnings: warnings
        )
    }

    // 从 JobsByPods 附近自动寻找同一 Xcode 工程的 Pods 安装目录。
    func detectCocoaPodsDirectory(near rootURL: URL) -> URL? {
        var candidate = rootURL.standardizedFileURL
        for _ in 0..<8 {
            if isCocoaPodsDirectory(candidate) {
                return candidate
            }
            let nestedPodsURL = candidate.appendingPathComponent("Pods", isDirectory: true)
            if isCocoaPodsDirectory(nestedPodsURL) {
                return nestedPodsURL
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        };return nil
    }

    // 导入 pod install 生成的项目 Pods 快照，并用锁文件、下载缓存和 Specs 自动建立外源 Pod 索引。
    func scanCocoaPodsSnapshot(
        podsDirectoryURL: URL,
        onProgress: @escaping (Int, Int, String) -> Void
    ) throws -> CocoaPodsSnapshotResult {
        let standardizedPodsURL = podsDirectoryURL.standardizedFileURL
        guard isCocoaPodsDirectory(standardizedPodsURL) else {
            throw BuilderError.scan(
                "所选目录不是有效的 CocoaPods Pods 目录：\(standardizedPodsURL.path)\n" +
                "目录中必须存在 Manifest.lock，工程根目录中应存在 Podfile.lock。"
            )
        }
        let manifestURL = standardizedPodsURL.appendingPathComponent("Manifest.lock")
        let projectLockURL = standardizedPodsURL
            .deletingLastPathComponent()
            .appendingPathComponent("Podfile.lock")
        let manifestData = try Data(contentsOf: manifestURL)
        let lockfileURL: URL
        if FileManager.default.fileExists(atPath: projectLockURL.path) {
            let projectLockData = try Data(contentsOf: projectLockURL)
            guard projectLockData == manifestData else {
                throw BuilderError.scan(
                    "Podfile.lock 与 Pods/Manifest.lock 不一致。\n" +
                    "请先在原 Xcode 工程执行 pod install，让项目 Pods 快照恢复一致后再导入。"
                )
            }
            lockfileURL = projectLockURL
        } else {
            lockfileURL = manifestURL
        }
        guard let lockContents = String(data: manifestData, encoding: .utf8) else {
            throw BuilderError.scan("无法以 UTF-8 读取 CocoaPods 锁文件：\(manifestURL.path)")
        }
        let lockedPods = try parseLockedPods(lockContents)
        guard lockedPods.isEmpty == false else {
            throw BuilderError.scan("CocoaPods 锁文件中没有解析到任何已安装 Pod。")
        }

        var specs: [PodSpecRecord] = []
        var warnings: [String] = []
        for (index, lockedPod) in lockedPods.enumerated() {
            onProgress(index + 1, lockedPods.count, lockedPod.name)
            let source = installedSource(
                name: lockedPod.name,
                version: lockedPod.version,
                podsDirectoryURL: standardizedPodsURL
            )
            if let podspecURL = metadataPodspecURL(
                name: lockedPod.name,
                version: lockedPod.version,
                podsDirectoryURL: standardizedPodsURL
            ) {
                do {
                    let data = try Data(contentsOf: podspecURL)
                    let spec = try makePodSpecRecord(
                        data: data,
                        podspecURL: podspecURL,
                        sourceKind: source.kind,
                        directoryURL: source.directoryURL
                    )
                    guard spec.name == lockedPod.name,
                          spec.version == lockedPod.version else {
                        throw BuilderError.scan(
                            "元数据为 \(spec.name) \(spec.version)，锁文件要求 \(lockedPod.name) \(lockedPod.version)。"
                        )
                    }
                    specs.append(spec)
                    continue
                } catch {
                    warnings.append(
                        "\(lockedPod.name) \(lockedPod.version) 元数据读取失败：\(error.localizedDescription)"
                    )
                }
            }
            specs.append(fallbackLockedSpec(
                lockedPod,
                lockfileURL: lockfileURL,
                sourceKind: source.kind,
                directoryURL: source.directoryURL
            ))
            warnings.append(
                "\(lockedPod.name) \(lockedPod.version) 未找到完整 podspec 元数据；" +
                "已使用锁文件关系继续自动解析，许可证和系统依赖将在 pod install / 预编译阶段复核。"
            )
        };return CocoaPodsSnapshotResult(
            podsDirectoryURL: standardizedPodsURL,
            lockfileURL: lockfileURL,
            specs: specs.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            warnings: warnings,
            installedPodCount: lockedPods.count
        )
    }

    // 查询 CocoaPods Specs 中的远程 Pod 元数据，但不执行正式打包。
    func queryRemote(
        dependency: PodDependency,
        onOutput: @escaping (String) -> Void
    ) async throws -> PodSpecRecord {
        let result = try await runner.run(
            executable: podExecutable,
            arguments: ["spec", "which", dependency.rootName, "--no-ansi"],
            onOutput: { _ in }
        )
        if result.standardError.isEmpty == false {
            onOutput(result.standardError)
        }
        guard result.exitCode == 0 else {
            throw BuilderError.command(
                "\(podExecutable) spec which \(dependency.rootName)",
                result.exitCode,
                commandDiagnostic(result)
            )
        }
        let candidatePaths = result.standardOutput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard let podspecPath = candidatePaths.last else {
            throw BuilderError.scan("CocoaPods Specs 中没有找到 \(dependency.rootName)。")
        }

        let remoteSpec = try await parsePodspec(
            at: URL(fileURLWithPath: podspecPath),
            sourceKindOverride: .remote,
            onOutput: onOutput
        )
        guard VersionRequirement.matches(
            version: remoteSpec.version,
            requirement: dependency.requirement
        ) else {
            throw BuilderError.validation(
                "远程 \(remoteSpec.name) \(remoteSpec.version) 不满足 \(dependency.requirement)。"
            )
        };return remoteSpec
    }

    // 使用 CocoaPods IPC 将 podspec 转换成稳定 JSON 模型。
    func parsePodspec(
        at podspecURL: URL,
        sourceKindOverride: PodSourceKind? = nil,
        onOutput: @escaping (String) -> Void
    ) async throws -> PodSpecRecord {
        if podspecURL.lastPathComponent.lowercased().hasSuffix(".podspec.json") {
            return try makePodSpecRecord(
                data: Data(contentsOf: podspecURL),
                podspecURL: podspecURL,
                sourceKind: sourceKindOverride ?? classifyLocalSource(path: podspecURL.path),
                directoryURL: podspecURL.deletingLastPathComponent()
            )
        }
        let result = try await runner.run(
            executable: podExecutable,
            arguments: ["ipc", "spec", podspecURL.path, "--no-ansi"],
            currentDirectory: podspecURL.deletingLastPathComponent(),
            onOutput: { _ in }
        )
        if result.standardError.isEmpty == false {
            onOutput(result.standardError)
        }
        guard result.exitCode == 0 else {
            throw BuilderError.command(
                "\(podExecutable) ipc spec \(podspecURL.path)",
                result.exitCode,
                commandDiagnostic(result)
            )
        }
        guard let data = result.standardOutput.data(using: .utf8) else {
            throw BuilderError.scan("无法读取 podspec 的 JSON 输出：\(podspecURL.path)")
        };return try makePodSpecRecord(
            data: data,
            podspecURL: podspecURL,
            sourceKind: sourceKindOverride ?? classifyLocalSource(path: podspecURL.path),
            directoryURL: podspecURL.deletingLastPathComponent()
        )
    }

    // CocoaPods 机器可读输出不进入 UI，失败时只保留有限的诊断文本。
    private func commandDiagnostic(_ result: CommandResult) -> String {
        let rawDiagnostic = result.standardError.isEmpty
            ? result.standardOutput
            : result.standardError
        let maximumCharacterCount = 4_000
        guard rawDiagnostic.count > maximumCharacterCount else { return rawDiagnostic };return String(
            rawDiagnostic.suffix(maximumCharacterCount)
        )
    }

    // 将 podspec JSON 统一转换为构建器使用的来源模型。
    private func makePodSpecRecord(
        data: Data,
        podspecURL: URL,
        sourceKind: PodSourceKind,
        directoryURL: URL
    ) throws -> PodSpecRecord {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let version = json["version"] as? String else {
            throw BuilderError.scan("无法读取 podspec 的 name/version：\(podspecURL.path)")
        }
        let moduleName = (json["module_name"] as? String) ?? sanitizeModuleName(name)
        let dependencies = collectDependencies(
            from: json,
            parentName: name
        ).filter {
            $0.rootName != name
        }
        let frameworks = collectStringValues(key: "frameworks", from: json)
        let libraries = collectStringValues(key: "libraries", from: json)
        let resourceBundleNames = collectResourceBundleNames(from: json)
        let license = parseLicense(json["license"])
        let sourceURL = parseSourceURL(json["source"])

        return PodSpecRecord(
            name: name,
            version: version,
            moduleName: moduleName,
            podspecPath: podspecURL.path,
            directoryPath: directoryURL.path,
            sourceKind: sourceKind,
            license: license,
            sourceURL: sourceURL,
            summary: (json["summary"] as? String) ?? "",
            dependencies: dependencies,
            frameworks: frameworks,
            libraries: libraries,
            resourceBundleNames: resourceBundleNames
        )
    }

    // 判断目录是否为 pod install 生成并带有锁快照的 Pods 目录。
    private func isCocoaPodsDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue &&
            FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Manifest.lock").path
            )
    }

    // 解析 Podfile.lock 的 PODS 区域，并合并根 Pod 与 subspec 的传递依赖。
    private func parseLockedPods(_ contents: String) throws -> [LockedPod] {
        var isReadingPods = false
        var currentRootName = ""
        var catalog: [String: LockedPod] = [:]
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line == "PODS:" {
                isReadingPods = true
                continue
            }
            guard isReadingPods else { continue }
            if line.isEmpty == false, line.first?.isWhitespace == false {
                break
            }
            if line.hasPrefix("  - ") {
                let item = parseLockItem(String(line.dropFirst(4)))
                guard let version = item.value, version.isEmpty == false else { continue }
                let rootName = rootPodName(item.name)
                currentRootName = rootName
                if let existing = catalog[rootName], existing.version != version {
                    throw BuilderError.scan(
                        "锁文件中的 \(rootName) 同时出现 \(existing.version) 与 \(version)，无法自动仲裁。"
                    )
                }
                if catalog[rootName] == nil {
                    catalog[rootName] = LockedPod(
                        name: rootName,
                        version: version,
                        dependencies: []
                    )
                }
                continue
            }
            guard line.hasPrefix("    - "), currentRootName.isEmpty == false else {
                continue
            }
            let item = parseLockItem(String(line.dropFirst(6)))
            let dependencyRootName = rootPodName(item.name)
            guard dependencyRootName != currentRootName,
                  var lockedPod = catalog[currentRootName] else { continue }
            let dependency = PodDependency(
                name: item.name,
                requirement: item.value ?? "",
                requestedBy: currentRootName
            )
            if lockedPod.dependencies.contains(where: { $0.id == dependency.id }) == false {
                lockedPod.dependencies.append(dependency)
                catalog[currentRootName] = lockedPod
            }
        };return catalog.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // 解析锁文件中的 `PodName (版本或约束)` 单项。
    private func parseLockItem(_ rawValue: String) -> (name: String, value: String?) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(":") {
            value.removeLast()
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }
        guard value.hasSuffix(")"),
              let openingIndex = value.lastIndex(of: "(") else {
            return (value, nil)
        }
        let name = value[..<openingIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let requirementStart = value.index(after: openingIndex)
        let requirementEnd = value.index(before: value.endIndex)
        let requirement = String(value[requirementStart..<requirementEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines);return (name, requirement)
    }

    // 取 subspec 名称的根 Pod 部分。
    private func rootPodName(_ name: String) -> String {
        name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? name
    }

    // 按项目 Pods、CocoaPods 下载缓存、最后 Specs 的顺序确定实际源码来源。
    private func installedSource(
        name: String,
        version: String,
        podsDirectoryURL: URL
    ) -> (kind: PodSourceKind, directoryURL: URL) {
        let projectSourceURL = podsDirectoryURL.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: projectSourceURL.path) {
            return (.projectPods, projectSourceURL)
        }
        if let cacheSourceURL = cocoaPodsCacheSourceURL(name: name, version: version) {
            return (.cocoaPodsCache, cacheSourceURL)
        };return (.remote, podsDirectoryURL)
    }

    // 查找与锁定版本严格一致的 podspec 元数据。
    private func metadataPodspecURL(
        name: String,
        version: String,
        podsDirectoryURL: URL
    ) -> URL? {
        let localPodspecURL = podsDirectoryURL
            .appendingPathComponent("Local Podspecs", isDirectory: true)
            .appendingPathComponent("\(name).podspec.json")
        if FileManager.default.fileExists(atPath: localPodspecURL.path) {
            return localPodspecURL
        }
        if let cachePodspecURL = cocoaPodsCachePodspecURL(name: name, version: version) {
            return cachePodspecURL
        };return specsRepositoryPodspecURL(name: name, version: version)
    }

    // 查找 CocoaPods 下载缓存中的精确版本 podspec。
    private func cocoaPodsCachePodspecURL(name: String, version: String) -> URL? {
        let directoryURL = cocoaPodsCacheRootURL()
            .appendingPathComponent("Specs/Release", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil };return entries.filter {
            $0.lastPathComponent.hasPrefix("\(version)-") &&
                $0.lastPathComponent.hasSuffix(".podspec.json")
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last
    }

    // 查找 CocoaPods 下载缓存中的精确版本源码备份。
    private func cocoaPodsCacheSourceURL(name: String, version: String) -> URL? {
        let directoryURL = cocoaPodsCacheRootURL()
            .appendingPathComponent("Release", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil };return entries.filter {
            $0.lastPathComponent.hasPrefix("\(version)-")
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last
    }

    // 返回 CocoaPods 当前用户级下载缓存根目录。
    private func cocoaPodsCacheRootURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CocoaPods/Pods", isDirectory: true)
    }

    // 按 CocoaPods Specs 的名称哈希路径查找本机已有的精确版本元数据。
    private func specsRepositoryPodspecURL(name: String, version: String) -> URL? {
        let digest = Insecure.MD5.hash(data: Data(name.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.count >= 3 else { return nil }
        let repositoriesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cocoapods/repos", isDirectory: true)
        guard let repositories = try? FileManager.default.contentsOfDirectory(
            at: repositoriesURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for repositoryURL in repositories.sorted(by: { $0.path < $1.path }) {
            let podspecURL = repositoryURL
                .appendingPathComponent("Specs", isDirectory: true)
                .appendingPathComponent(String(digest.prefix(1)), isDirectory: true)
                .appendingPathComponent(String(digest.dropFirst().prefix(1)), isDirectory: true)
                .appendingPathComponent(String(digest.dropFirst(2).prefix(1)), isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(version, isDirectory: true)
                .appendingPathComponent("\(name).podspec.json")
            if FileManager.default.fileExists(atPath: podspecURL.path) {
                return podspecURL
            }
        };return nil
    }

    // 元数据缺失时仍以锁文件的精确版本和依赖关系构造可验证模型。
    private func fallbackLockedSpec(
        _ lockedPod: LockedPod,
        lockfileURL: URL,
        sourceKind: PodSourceKind,
        directoryURL: URL
    ) -> PodSpecRecord {
        PodSpecRecord(
            name: lockedPod.name,
            version: lockedPod.version,
            moduleName: sanitizeModuleName(lockedPod.name),
            podspecPath: lockfileURL.path,
            directoryPath: directoryURL.path,
            sourceKind: sourceKind,
            license: "未声明（待预编译复核）",
            sourceURL: sourceKind == .remote ? "CocoaPods Specs" : directoryURL.path,
            summary: "由 CocoaPods 锁文件自动导入。",
            dependencies: lockedPod.dependencies,
            frameworks: [],
            libraries: [],
            resourceBundleNames: []
        )
    }

    // 收集待解析目录中的 podspec，并跳过生成物、示例、测试和备份目录。
    private func collectPodspecURLs(rootURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw BuilderError.scan("无法遍历目录：\(rootURL.path)")
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if excludedDirectoryNames.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true,
                  url.pathExtension.lowercased() == "podspec" ||
                  url.lastPathComponent.lowercased().hasSuffix(".podspec.json") else {
                continue
            }
            results.append(url)
        };return results.sorted { $0.path < $1.path }
    }

    // 根据磁盘路径区分 Jobs 自建 Pod 与本地托管第三方 Pod。
    private func classifyLocalSource(path: String) -> PodSourceKind {
        let lowered = path.lowercased()
        if lowered.contains("/manualbyocpods@pods/") ||
            lowered.contains("/manualbyswiftpods@pods/") {
            return .localManual
        };return .localJobs
    }

    // 递归读取根 spec 与 subspec 中声明的依赖。
    private func collectDependencies(
        from json: [String: Any],
        parentName: String
    ) -> [PodDependency] {
        var dependencies: [PodDependency] = []
        appendDependencyDictionary(
            json["dependencies"],
            parentName: parentName,
            into: &dependencies
        )
        if let subspecs = json["subspecs"] as? [[String: Any]] {
            for subspec in subspecs {
                let subspecName = (subspec["name"] as? String) ?? parentName
                dependencies.append(contentsOf: collectDependencies(
                    from: subspec,
                    parentName: subspecName
                ))
            }
        }

        var seen: Set<String> = []
        return dependencies.filter { dependency in
            let key = dependency.id
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    // 解析 pod ipc spec 输出中的 dependency 字典。
    private func appendDependencyDictionary(
        _ rawValue: Any?,
        parentName: String,
        into dependencies: inout [PodDependency]
    ) {
        guard let dictionary = rawValue as? [String: Any] else { return }
        for (name, rawRequirement) in dictionary {
            let requirement: String
            if let values = rawRequirement as? [String] {
                requirement = values.joined(separator: ", ")
            } else if let value = rawRequirement as? String {
                requirement = value
            } else {
                requirement = ""
            }
            dependencies.append(PodDependency(
                name: name,
                requirement: requirement,
                requestedBy: parentName
            ))
        }
    }

    // 收集根 spec、平台配置和 subspec 中声明的字符串数组。
    private func collectStringValues(key: String, from json: [String: Any]) -> [String] {
        var values: [String] = []
        appendStringValue(json[key], into: &values)
        for platformKey in ["ios", "osx", "tvos", "watchos", "visionos"] {
            if let platform = json[platformKey] as? [String: Any] {
                appendStringValue(platform[key], into: &values)
            }
        }
        if let subspecs = json["subspecs"] as? [[String: Any]] {
            for subspec in subspecs {
                values.append(contentsOf: collectStringValues(key: key, from: subspec))
            }
        };return Array(Set(values)).sorted()
    }

    // 兼容字符串和字符串数组两种 podspec IPC 表达。
    private func appendStringValue(_ rawValue: Any?, into values: inout [String]) {
        if let value = rawValue as? String {
            values.append(value)
        } else if let array = rawValue as? [String] {
            values.append(contentsOf: array)
        }
    }

    // 收集资源 Bundle 名称，用于来源表与产物校验。
    private func collectResourceBundleNames(from json: [String: Any]) -> [String] {
        var names: [String] = []
        if let bundles = json["resource_bundles"] as? [String: Any] {
            names.append(contentsOf: bundles.keys)
        }
        if let subspecs = json["subspecs"] as? [[String: Any]] {
            for subspec in subspecs {
                names.append(contentsOf: collectResourceBundleNames(from: subspec))
            }
        };return Array(Set(names)).sorted()
    }

    // 将 podspec license 字符串或字典转换为可展示文本。
    private func parseLicense(_ rawValue: Any?) -> String {
        if let value = rawValue as? String {
            return value
        }
        if let dictionary = rawValue as? [String: Any] {
            return (dictionary["type"] as? String) ??
                (dictionary["file"] as? String) ??
                "未声明"
        };return "未声明"
    }

    // 提取 podspec source 中可追溯的仓库或下载地址。
    private func parseSourceURL(_ rawValue: Any?) -> String {
        guard let dictionary = rawValue as? [String: Any] else { return "" }
        for key in ["git", "http", "path"] {
            if let value = dictionary[key] as? String {
                let suffix = (dictionary["tag"] as? String).map { " @ \($0)" } ?? ""
                return value + suffix
            }
        };return ""
    }

    // 把 Pod 名转换为 Swift/Clang 可用的默认模块名。
    private func sanitizeModuleName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" };return String(scalars)
    }

    private struct LockedPod {
        let name: String
        let version: String
        var dependencies: [PodDependency]
    }
}

enum VersionRequirement {
    // 判断本地或远程版本是否满足 podspec 常用版本约束。
    static func matches(version: String, requirement: String) -> Bool {
        let trimmed = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return true }
        let constraints = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false };return constraints.allSatisfy { matchesSingle(version: version, constraint: $0) }
    }

    // 判断一个比较操作符约束。
    private static func matchesSingle(version: String, constraint: String) -> Bool {
        let operators = ["~>", ">=", "<=", ">", "<", "="]
        let matchedOperator = operators.first(where: { constraint.hasPrefix($0) })
        let expected = constraint
            .replacingOccurrences(of: matchedOperator ?? "", with: "", options: [.anchored])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected.isEmpty == false else { return true }
        let comparison = compare(version, expected)

        switch matchedOperator {
        /// CocoaPods 的兼容版本约束
        case "~>":
            let upperBound = pessimisticUpperBound(expected)
            return comparison != .orderedAscending && compare(version, upperBound) == .orderedAscending
        /// 大于或等于
        case ">=":
            return comparison != .orderedAscending
        /// 小于或等于
        case "<=":
            return comparison != .orderedDescending
        /// 严格大于
        case ">":
            return comparison == .orderedDescending
        /// 严格小于
        case "<":
            return comparison == .orderedAscending
        /// 等于或没有显式操作符
        case "=", nil:
            return comparison == .orderedSame
        /// 未识别的操作符交给 CocoaPods 最终校验
        default:
            return true
        }
    }

    // 比较两个点分版本号，忽略预发布后缀。
    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericComponents(lhs)
        let right = numericComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue {
                return .orderedAscending
            }
            if leftValue > rightValue {
                return .orderedDescending
            }
        };return .orderedSame
    }

    // 提取版本字符串中的数字组件。
    private static func numericComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { component in
                let digits = component.prefix(while: { $0.isNumber })
                return Int(digits) ?? 0
            }
    }

    // 计算 RubyGems `~>` 约束的排他上界。
    private static func pessimisticUpperBound(_ version: String) -> String {
        var components = numericComponents(version)
        if components.count <= 1 {
            return "\((components.first ?? 0) + 1).0.0"
        }
        let incrementIndex = components.count - 2
        components[incrementIndex] += 1
        for index in (incrementIndex + 1)..<components.count {
            components[index] = 0
        };return components.map(String.init).joined(separator: ".")
    }
}
