//
//  SmokeMain.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

@main
enum SmokeMain {
    // 真实解析一个本地 podspec，并验证生成的最小 Xcode 工程。
    static func main() async throws {
        guard let podExecutable = ToolLocator.executable(named: "pod") else {
            throw BuilderError.environment("冒烟测试找不到 pod 命令。")
        }
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

        let defaultPodDirectory = """
        /Users/jobs/Documents/Github/JobsBaseConfig/JobsBaseConfig@JobsSwiftBaseConfigDemo/JobsByPods/JobsSwiftPatch@Pods
        """.trimmingCharacters(in: .whitespacesAndNewlines)
        let podDirectory = CommandLine.arguments.dropFirst().first ?? defaultPodDirectory
        let runner = CommandRunner()
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
            allSpecs: [rootSpec]
        )

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
        print("PROJECT_LIST=PackagingHost")
    }
}
