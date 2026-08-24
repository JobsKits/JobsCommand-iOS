//
//  ImportedPodsInstallMain.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年8月24日，星期一.
//

import Foundation

@main
enum ImportedPodsInstallMain {
    // 用 AFSecurityPolicyExtra 真实依赖闭包验证已安装外源 Pod 不再联网下载。
    static func main() async throws {
        guard let podExecutable = ToolLocator.executable(named: "pod") else {
            throw BuilderError.environment("外源 Pod 回归测试找不到 pod 命令。")
        }
        let runner = CommandRunner()
        let service = PodspecService(
            runner: runner,
            podExecutable: podExecutable
        )
        let jobsByPodsURL = URL(
            fileURLWithPath: "/Users/jobs/Documents/Github/JobsOCBaseConfigDemo@ByPods/JobsByPods",
            isDirectory: true
        )
        let podsURL = URL(
            fileURLWithPath: "/Users/jobs/Documents/Github/JobsOCBaseConfigDemo@ByPods/Pods",
            isDirectory: true
        )
        let localScan = try await service.scan(
            rootURL: jobsByPodsURL,
            onProgress: { _, _, _ in },
            onOutput: { _ in }
        )
        let snapshot = try service.scanCocoaPodsSnapshot(
            podsDirectoryURL: podsURL,
            onProgress: { _, _, _ in }
        )
        var catalog = Dictionary(uniqueKeysWithValues: snapshot.specs.map {
            ($0.name, $0)
        })
        for spec in localScan.specs {
            catalog[spec.name] = spec
        }
        guard let rootSpec = catalog["AFSecurityPolicyExtra"] else {
            throw BuilderError.validation("没有找到 AFSecurityPolicyExtra 主 Pod。")
        }

        var queue = [rootSpec]
        var resolvedByName: [String: PodSpecRecord] = [:]
        while let spec = queue.first {
            queue.removeFirst()
            guard resolvedByName[spec.name] == nil else { continue }
            resolvedByName[spec.name] = spec
            for dependency in spec.dependencies {
                guard let dependencySpec = catalog[dependency.rootName],
                      VersionRequirement.matches(
                        version: dependencySpec.version,
                        requirement: dependency.requirement
                      ) else {
                    throw BuilderError.validation(
                        "\(spec.name) 的依赖 \(dependency.rootName) \(dependency.requirement) 没有命中精确来源。"
                    )
                }
                queue.append(dependencySpec)
            }
        }
        let allSpecs = Array(resolvedByName.values)
        let externalNames = Set(allSpecs.filter {
            $0.sourceKind == .projectPods || $0.sourceKind == .cocoaPodsCache
        }.map(\.name))
        let expectedExternalNames: Set<String> = [
            "AFNetworking", "GKNavigationBar", "SDWebImage", "YTKNetwork"
        ]
        guard expectedExternalNames.isSubset(of: externalNames) else {
            throw BuilderError.validation(
                "AFSecurityPolicyExtra 的外源闭包不完整：\(externalNames.sorted().joined(separator: "、"))"
            )
        }

        let sessionURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JobsPodBinaryBuilder-ImportedPods-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: sessionURL)
        }
        try ProjectGenerator.writePackagingWorkspace(
            at: sessionURL,
            rootSpec: rootSpec,
            allSpecs: allSpecs
        )
        let podfile = try String(
            contentsOf: sessionURL.appendingPathComponent("Podfile"),
            encoding: .utf8
        )
        for name in expectedExternalNames {
            guard podfile.contains(
                "pod '\(name)', :path => 'ImportedPods/\(name)'"
            ) else {
                throw BuilderError.validation("\(name) 没有生成 ImportedPods 本地引用。")
            }
        }

        let installResult = try await runner.run(
            executable: podExecutable,
            arguments: ["install", "--no-repo-update", "--verbose", "--no-ansi"],
            currentDirectory: sessionURL,
            onOutput: { _ in }
        )
        guard installResult.exitCode == 0 else {
            throw BuilderError.command(
                "\(podExecutable) install --no-repo-update --verbose --no-ansi",
                installResult.exitCode,
                installResult.output
            )
        }
        let lowercaseOutput = installResult.output.lowercased()
        guard lowercaseOutput.contains("git download") == false,
              lowercaseOutput.contains("cloning into") == false else {
            throw BuilderError.validation("ImportedPods 回归测试仍然触发了 Git 下载。")
        }

        if CommandLine.arguments.contains("--prebuild") {
            let workspaceURL = sessionURL.appendingPathComponent(
                "PackagingHost.xcworkspace"
            )
            let buildConfigurations = [
                (
                    sdk: "iphoneos",
                    destination: "generic/platform=iOS",
                    derivedDataName: "PreflightDevice"
                ),
                (
                    sdk: "iphonesimulator",
                    destination: "generic/platform=iOS Simulator",
                    derivedDataName: "PreflightSimulator"
                )
            ]
            for configuration in buildConfigurations {
                let buildResult = try await runner.run(
                    executable: "/usr/bin/xcodebuild",
                    arguments: [
                        "-workspace", workspaceURL.path,
                        "-scheme", "PackagingHost",
                        "-configuration", "Release",
                        "-sdk", configuration.sdk,
                        "-destination", configuration.destination,
                        "-derivedDataPath", sessionURL.appendingPathComponent(
                            "DerivedData/\(configuration.derivedDataName)"
                        ).path,
                        "BUILD_LIBRARY_FOR_DISTRIBUTION=YES",
                        "SKIP_INSTALL=NO",
                        "CODE_SIGNING_ALLOWED=NO",
                        "CODE_SIGNING_REQUIRED=NO",
                        "clean",
                        "build"
                    ],
                    currentDirectory: sessionURL,
                    onOutput: { _ in }
                )
                guard buildResult.exitCode == 0 else {
                    throw BuilderError.command(
                        "xcodebuild \(configuration.sdk)",
                        buildResult.exitCode,
                        buildResult.output
                    )
                }
            }
            print("DUAL_SDK_PREBUILD=OK")
        }

        if CommandLine.arguments.contains("--package") {
            let outputParentURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "JobsPodBinaryBuilder-ImportedPodsOutput-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: outputParentURL,
                withIntermediateDirectories: true
            )
            defer {
                try? FileManager.default.removeItem(at: outputParentURL)
            }
            let engine = PackagingEngine(
                runner: runner,
                podExecutable: podExecutable
            )
            let preparedSession = try await engine.prepare(
                rootSpec: rootSpec,
                allSpecs: allSpecs,
                onStage: { _ in },
                onOutput: { _ in }
            )
            defer {
                engine.discard(session: preparedSession)
            }
            let outcome = try await engine.package(
                session: preparedSession,
                outputParentURL: outputParentURL,
                onStage: { _ in },
                onOutput: { _ in }
            )
            guard outcome.xcframeworkCount == allSpecs.count,
                  FileManager.default.fileExists(
                    atPath: outcome.outputURL.appendingPathComponent(
                        "ConsumerDemo/ConsumerDemo.xcworkspace"
                    ).path
                  ) else {
                throw BuilderError.validation("AFSecurityPolicyExtra 端到端二进制产物不完整。")
            }
            print("FULL_BINARY_PACKAGE=OK")
            print("XCFRAMEWORKS=\(outcome.xcframeworkCount)")
            print("RESOURCE_BUNDLES=\(outcome.resourceBundleCount)")
        }

        print("IMPORTED_PODS_INSTALL_OK")
        print("ROOT=\(rootSpec.name) \(rootSpec.version)")
        print("CLOSURE=\(allSpecs.count)")
        print("EXTERNAL=\(externalNames.sorted().joined(separator: ","))")
        print("NETWORK_DOWNLOAD=NO")
    }
}
