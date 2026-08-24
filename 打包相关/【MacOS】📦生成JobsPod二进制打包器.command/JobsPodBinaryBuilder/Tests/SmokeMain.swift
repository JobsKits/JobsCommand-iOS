//
//  SmokeMain.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

private final class SmokeOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var callbackCount = 0

    func append(_ text: String) {
        lock.lock()
        output.append(text)
        callbackCount += 1
        lock.unlock()
    }

    func snapshot() -> (output: String, callbackCount: Int) {
        lock.lock()
        let snapshot = (output, callbackCount)
        lock.unlock()
        return snapshot
    }
}

@main
enum SmokeMain {
    // 真实解析一个本地 podspec，并验证生成的最小 Xcode 工程。
    static func main() async throws {
        guard let podExecutable = ToolLocator.executable(named: "pod") else {
            throw BuilderError.environment("冒烟测试找不到 pod 命令。")
        }
        let runner = CommandRunner()
        guard VersionRequirement.matches(
            version: "1.2.3",
            requirement: "~> 1.2"
        ), VersionRequirement.matches(
            version: "2.0.0",
            requirement: ">= 1.0, < 3.0"
        ) else {
            throw BuilderError.validation("版本约束判断冒烟测试失败。")
        }
        let diagnosticCandidates = BuildDiagnostic.missingDependencyCandidates(
            from: "error: no such module 'JobsMissingKit'"
        )
        guard diagnosticCandidates == ["JobsMissingKit"] else {
            throw BuilderError.validation("缺失依赖诊断冒烟测试失败。")
        }
        let downloadFailure = """
        [!] Error installing GKNavigationBar
        error: RPC failed; curl 92 HTTP/2 stream was not closed cleanly
        fatal: the remote end hung up unexpectedly
        \(Array(repeating: "downloader.rb:110:in download_source", count: 35).joined(separator: "\n"))
        """
        let downloadMessage = BuildDiagnostic.userFacingMessage(
            command: "pod install",
            exitCode: 1,
            output: downloadFailure
        )
        guard downloadMessage.contains("关键错误："),
              downloadMessage.contains("Error installing GKNavigationBar"),
              downloadMessage.contains("RPC failed") else {
            throw BuilderError.validation("外源 Pod 下载失败原因提取冒烟测试失败。")
        }
        let binaryPodspec = ProjectGenerator.binaryPodspec(
            rootSpec: PodSpecRecord(
                name: "BinarySmoke",
                version: "1.0.0",
                moduleName: "BinarySmoke",
                podspecPath: "/tmp/BinarySmoke.podspec",
                directoryPath: "/tmp/BinarySmoke",
                sourceKind: .localJobs,
                license: "MIT",
                sourceURL: "",
                summary: "",
                dependencies: [],
                frameworks: [],
                libraries: [],
                resourceBundleNames: []
            ),
            dependencySpecs: [],
            frameworkRelativePaths: ["BinarySmoke.xcframework"],
            hasResources: true
        )
        guard binaryPodspec.contains("spec.resources = 'Resources/*.bundle'"),
              binaryPodspec.contains("Resources/**/*") == false else {
            throw BuilderError.validation("二进制资源 Bundle 整包引用冒烟测试失败。")
        }
        let streamCapture = SmokeOutputCapture()
        let streamResult = try await runner.run(
            executable: "/bin/zsh",
            arguments: [
                "-c",
                "print -r -- '{\"status\":\"ok\"}'; print -r -- '编码警告' >&2"
            ],
            onOutput: { text in
                streamCapture.append(text)
            }
        )
        let streamSnapshot = streamCapture.snapshot()
        guard streamResult.standardOutput.contains("\"status\":\"ok\""),
              streamResult.standardError.contains("编码警告"),
              streamResult.output.contains("编码警告"),
              streamSnapshot.output.contains("\"status\":\"ok\""),
              streamSnapshot.output.contains("编码警告"),
              streamSnapshot.callbackCount <= 4 else {
            throw BuilderError.validation("子进程标准输出与错误输出分离失败。")
        }

        let defaultPodDirectory = """
        /Users/jobs/Documents/Github/JobsBaseConfig/JobsBaseConfig@JobsSwiftBaseConfigDemo/JobsByPods/JobsSwiftPatch@Pods
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        let podDirectory = CommandLine.arguments.dropFirst().first ?? defaultPodDirectory
        let service = PodspecService(
            runner: runner,
            podExecutable: podExecutable
        )
        let scanResult = try await service.scan(
            rootURL: URL(fileURLWithPath: podDirectory, isDirectory: true),
            onProgress: { _, _, _ in },
            onOutput: { _ in }
        )
        guard let rootSpec = scanResult.specs.first else {
            throw BuilderError.validation("真实 podspec 没有解析出 Pod 模型。")
        }
        var installedAFNetworkingSpec: PodSpecRecord?
        let cocoaPodsDirectory = URL(
            fileURLWithPath: "/Users/jobs/Documents/Github/JobsOCBaseConfigDemo@ByPods/Pods",
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: cocoaPodsDirectory.path) {
            let snapshot = try service.scanCocoaPodsSnapshot(
                podsDirectoryURL: cocoaPodsDirectory,
                onProgress: { _, _, _ in }
            )
            installedAFNetworkingSpec = snapshot.specs.first(where: {
                $0.name == "AFNetworking" &&
                    $0.version == "4.0.1" &&
                    $0.sourceKind == .projectPods
            })
            guard installedAFNetworkingSpec != nil else {
                throw BuilderError.validation("项目 Pods 自动导入没有锁定 AFNetworking 4.0.1。")
            }
            let automaticallyResolvedNames = Set(snapshot.specs.map(\.name))
            guard ["AFNetworking", "GKNavigationBar", "SDWebImage", "YTKNetwork"].allSatisfy({
                automaticallyResolvedNames.contains($0)
            }) else {
                throw BuilderError.validation("截图中的四项外源依赖没有全部进入项目 Pods 自动索引。")
            }
        }

        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JobsPodBinaryBuilder-Smoke-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: testURL)
        }
        try ProjectGenerator.writePackagingWorkspace(
            at: testURL,
            rootSpec: rootSpec,
            allSpecs: [rootSpec] + [installedAFNetworkingSpec].compactMap { $0 }
        )
        if installedAFNetworkingSpec != nil {
            let generatedPodfile = try String(
                contentsOf: testURL.appendingPathComponent("Podfile"),
                encoding: .utf8
            )
            let importedSourceURL = testURL
                .appendingPathComponent("ImportedPods/AFNetworking", isDirectory: true)
            guard generatedPodfile.contains(
                "pod 'AFNetworking', :path => 'ImportedPods/AFNetworking'"
            ), FileManager.default.fileExists(
                atPath: importedSourceURL.appendingPathComponent("AFNetworking").path
            ), FileManager.default.fileExists(
                atPath: importedSourceURL.appendingPathComponent(
                    "AFNetworking.podspec.json"
                ).path
            ) else {
                throw BuilderError.validation("项目 Pods 没有导入会话沙盒并作为本地 Pod 引用。")
            }
        }

        let projectURL = testURL.appendingPathComponent("PackagingHost.xcodeproj")
        let listResult = try await runner.run(
            executable: "/usr/bin/xcodebuild",
            arguments: ["-project", projectURL.path, "-list"],
            onOutput: { _ in }
        )
        guard listResult.exitCode == 0,
              listResult.output.contains("PackagingHost") else {
            throw BuilderError.command(
                "xcodebuild -project \(projectURL.path) -list",
                listResult.exitCode,
                listResult.output
            )
        }

        print("SMOKE_OK")
        print("POD=\(rootSpec.name) \(rootSpec.version)")
        print("DEPENDENCIES=\(rootSpec.dependencies.count)")
        print("COCOAPODS_SNAPSHOT=AUTO")
        print("PROJECT_LIST=PackagingHost")
    }
}
