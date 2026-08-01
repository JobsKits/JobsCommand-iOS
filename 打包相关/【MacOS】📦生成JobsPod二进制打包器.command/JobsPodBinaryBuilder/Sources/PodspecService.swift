//
//  PodspecService.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

struct PodspecScanResult {
    let specs: [PodSpecRecord]
    let warnings: [String]
}

final class PodspecService {
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
            throw BuilderError.scan("发现了 podspec，但没有任何文件可以被 CocoaPods 正确解析。")
        }
        return PodspecScanResult(
            specs: parsedSpecs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            warnings: warnings
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
            onOutput: onOutput
        )
        guard result.exitCode == 0 else {
            throw BuilderError.command(
                "\(podExecutable) spec which \(dependency.rootName)",
                result.exitCode,
                result.output
            )
        }
        let candidatePaths = result.output
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
        let result = try await runner.run(
            executable: podExecutable,
            arguments: ["ipc", "spec", podspecURL.path, "--no-ansi"],
            currentDirectory: podspecURL.deletingLastPathComponent(),
            onOutput: onOutput
        )
        guard result.exitCode == 0 else {
            throw BuilderError.command(
                "\(podExecutable) ipc spec \(podspecURL.path)",
                result.exitCode,
                result.output
            )
        }
        guard let data = result.output.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String,
              let version = json["version"] as? String else {
            throw BuilderError.scan("无法读取 podspec 的 name/version：\(podspecURL.path)")
        }

        let sourceKind = sourceKindOverride ?? classifyLocalSource(path: podspecURL.path)
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
            directoryPath: podspecURL.deletingLastPathComponent().path,
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
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(scalars)
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
            .filter { $0.isEmpty == false }
        return constraints.allSatisfy { matchesSingle(version: version, constraint: $0) }
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
