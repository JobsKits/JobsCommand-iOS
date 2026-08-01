//
//  Models.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

enum PodSourceKind: String, Codable, CaseIterable {
    case localJobs
    case localManual
    case localSupplement
    case remote

    var displayName: String {
        switch self {
        /// Jobs 自建 Pod
        case .localJobs:
            return "Jobs 本地"
        /// 本地托管的第三方 Pod
        case .localManual:
            return "本地托管第三方"
        /// 用户本次补充的本地 Pod
        case .localSupplement:
            return "补充本地"
        /// CocoaPods 远程 Pod
        case .remote:
            return "CocoaPods 远程"
        }
    }

    var isLocal: Bool {
        self != .remote
    }
}

struct PodDependency: Hashable, Codable, Identifiable {
    let name: String
    let requirement: String
    let requestedBy: String

    var id: String {
        "\(requestedBy)|\(name)|\(requirement)"
    }

    var rootName: String {
        name.split(separator: "/", maxSplits: 1).first.map(String.init) ?? name
    }
}

struct PodSpecRecord: Hashable, Codable, Identifiable {
    let name: String
    let version: String
    let moduleName: String
    let podspecPath: String
    let directoryPath: String
    let sourceKind: PodSourceKind
    let license: String
    let sourceURL: String
    let summary: String
    let dependencies: [PodDependency]
    let frameworks: [String]
    let libraries: [String]
    let resourceBundleNames: [String]

    var id: String {
        "\(sourceKind.rawValue)|\(name)|\(podspecPath)"
    }
}

enum DependencyResolutionState: String, Codable {
    case resolvedLocal
    case resolvedRemote
    case unresolved
    case versionConflict

    var displayName: String {
        switch self {
        /// 已绑定本地路径
        case .resolvedLocal:
            return "本地已绑定"
        /// 已经用户确认远程来源
        case .resolvedRemote:
            return "远程已确认"
        /// 尚未确认依赖来源
        case .unresolved:
            return "等待来源确认"
        /// 本地版本不满足约束
        case .versionConflict:
            return "版本冲突"
        }
    }
}

struct DependencyResolutionRow: Hashable, Identifiable {
    let dependency: PodDependency
    let state: DependencyResolutionState
    let resolvedSpec: PodSpecRecord?
    let detail: String

    var id: String {
        dependency.id
    }
}

struct ProvenanceRow: Hashable, Codable, Identifiable {
    let name: String
    let relationship: String
    let version: String
    let sourceType: String
    let sourceIdentity: String
    let packagingMode: String
    let license: String
    let verification: String
    let fingerprint: String

    var id: String {
        "\(name)|\(version)|\(sourceType)"
    }
}

enum BuildStage: String {
    case idle
    case scanning
    case resolving
    case installing
    case validatingProject
    case prebuildingDevice
    case prebuildingSimulator
    case awaitingConfirmation
    case buildingDevice
    case buildingSimulator
    case assembling
    case validatingConsumer
    case completed
    case cancelled
    case failed

    var title: String {
        switch self {
        /// 尚未开始任务
        case .idle:
            return "等待导入"
        /// 正在扫描本地 Pod
        case .scanning:
            return "扫描本地 Pod"
        /// 正在解析依赖闭包
        case .resolving:
            return "解析依赖闭包"
        /// 正在执行 CocoaPods 安装
        case .installing:
            return "执行 pod install"
        /// 正在验证生成工程
        case .validatingProject:
            return "验证 Pods 工程"
        /// 正在预编译真机切片
        case .prebuildingDevice:
            return "预编译 iPhoneOS"
        /// 正在预编译模拟器切片
        case .prebuildingSimulator:
            return "预编译 Simulator"
        /// 正在等待来源表确认
        case .awaitingConfirmation:
            return "等待来源确认"
        /// 正在正式构建真机切片
        case .buildingDevice:
            return "正式构建 iPhoneOS"
        /// 正在正式构建模拟器切片
        case .buildingSimulator:
            return "正式构建 Simulator"
        /// 正在组装二进制 SDK
        case .assembling:
            return "组装 XCFramework"
        /// 正在验证最终消费工程
        case .validatingConsumer:
            return "验证消费 Demo"
        /// 全部任务已经完成
        case .completed:
            return "打包完成"
        /// 用户取消当前任务
        case .cancelled:
            return "任务已取消"
        /// 当前任务执行失败
        case .failed:
            return "任务失败"
        }
    }

    var progress: Double {
        switch self {
        /// 尚未开始任务
        case .idle:
            return 0
        /// 正在扫描本地 Pod
        case .scanning:
            return 0.05
        /// 正在解析依赖闭包
        case .resolving:
            return 0.10
        /// 正在执行 CocoaPods 安装
        case .installing:
            return 0.28
        /// 正在验证生成工程
        case .validatingProject:
            return 0.34
        /// 正在预编译真机切片
        case .prebuildingDevice:
            return 0.38
        /// 正在预编译模拟器切片
        case .prebuildingSimulator:
            return 0.42
        /// 正在等待来源表确认
        case .awaitingConfirmation:
            return 0.45
        /// 正在正式构建真机切片
        case .buildingDevice:
            return 0.62
        /// 正在正式构建模拟器切片
        case .buildingSimulator:
            return 0.78
        /// 正在组装二进制 SDK
        case .assembling:
            return 0.92
        /// 正在验证最终消费工程
        case .validatingConsumer:
            return 0.98
        /// 全部任务已经完成
        case .completed:
            return 1
        /// 用户取消当前任务
        case .cancelled:
            return 0
        /// 当前任务执行失败
        case .failed:
            return 0
        }
    }
}

struct PreparedBuildSession {
    let rootSpec: PodSpecRecord
    let allSpecs: [PodSpecRecord]
    let workspaceURL: URL
    let sessionURL: URL
    let provenanceRows: [ProvenanceRow]
    let sourceFingerprint: String
}

struct CommandResult {
    let exitCode: Int32
    let output: String
}

enum BuilderError: LocalizedError {
    case environment(String)
    case scan(String)
    case duplicatePod(String, [String])
    case unresolvedDependencies([String])
    case command(String, Int32, String)
    case validation(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        /// 环境不满足执行要求
        case .environment(let message):
            return message
        /// 本地 Pod 扫描失败
        case .scan(let message):
            return message
        /// 本地存在重复 Pod 名
        case .duplicatePod(let name, let paths):
            return "发现重复的本地 Pod 名 \(name)：\n\(paths.joined(separator: "\n"))"
        /// 依赖来源尚未闭环
        case .unresolvedDependencies(let names):
            return "仍有未解决或版本冲突的依赖：\(names.joined(separator: "、"))"
        /// 外部命令执行失败
        case .command(let command, let code, let output):
            return BuildDiagnostic.userFacingMessage(
                command: command,
                exitCode: code,
                output: output
            )
        /// 构建或产物验证失败
        case .validation(let message):
            return message
        /// 用户取消任务
        case .cancelled:
            return "任务已取消"
        }
    }
}

enum BuildDiagnostic {
    // 从 CocoaPods、Clang、Swift 和链接器输出中提取疑似缺失依赖。
    static func missingDependencyCandidates(from output: String) -> [String] {
        let patterns = [
            #"no such module ['"]([^'"]+)['"]"#,
            #"Could not build module ['"]([^'"]+)['"]"#,
            #"module ['"]([^'"]+)['"] not found"#,
            #"fatal error: ['"]([^/'"]+)(?:/[^'"]+)?['"] file not found"#,
            #"framework ['"]([^'"]+)['"] not found"#,
            #"library not found for -l([A-Za-z0-9_+.-]+)"#
        ]
        var candidates: Set<String> = []
        for pattern in patterns {
            guard let regularExpression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            let range = NSRange(output.startIndex..., in: output)
            for match in regularExpression.matches(
                in: output,
                options: [],
                range: range
            ) where match.numberOfRanges > 1 {
                guard let candidateRange = Range(match.range(at: 1), in: output) else {
                    continue
                }
                let candidate = String(output[candidateRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.isEmpty == false {
                    candidates.insert(candidate)
                }
            }
        };return candidates.sorted()
    }

    // 生成适合弹窗的精简错误，同时把完整命令输出保留在实时日志中。
    static func userFacingMessage(
        command: String,
        exitCode: Int32,
        output: String
    ) -> String {
        let candidates = missingDependencyCandidates(from: output)
        let dependencyHint: String
        if candidates.isEmpty {
            dependencyHint = ""
        } else {
            dependencyHint = """

            疑似缺少的依赖、模块或头文件：
            \(candidates.map { "• \($0)" }.joined(separator: "\n"))

            请检查相关 *.podspec 是否遗漏 spec.dependency。
            如果它是自建 Pod，下次把对应本地目录一起导入；如果它是第三方 Pod，返回依赖表后确认从 CocoaPods 获取。
            """
        }
        let tailLines = output
            .split(whereSeparator: \.isNewline)
            .suffix(28)
            .joined(separator: "\n")
        return """
        命令执行失败（\(exitCode)）：
        \(command)
        \(dependencyHint)

        末尾日志：
        \(tailLines)

        完整输出仍保留在界面的实时构建日志中。
        """
    }
}
