//
//  PackageSmokeMain.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

@main
enum PackageSmokeMain {
    // 对零依赖 Jobs 本地 Pod 执行端到端二进制打包冒烟测试。
    static func main() async throws {
        guard let podExecutable = ToolLocator.executable(named: "pod") else {
            throw BuilderError.environment("端到端测试找不到 pod 命令。")
        }
        let podDirectory = """
        /Users/jobs/Documents/Github/JobsBaseConfig/JobsBaseConfig@JobsSwiftBaseConfigDemo/JobsByPods/JobsSwiftPatch@Pods
        """.trimmingCharacters(in: .whitespacesAndNewlines)
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
            throw BuilderError.validation("JobsSwiftPatch podspec 解析失败。")
        }

        let testOutputRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "JobsPodBinaryBuilder-PackageSmoke-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: testOutputRoot,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: testOutputRoot)
        }

        let engine = PackagingEngine(
            runner: runner,
            podExecutable: podExecutable
        )
        let prepared = try await engine.prepare(
            rootSpec: rootSpec,
            allSpecs: [rootSpec],
            onStage: { stage in
                print("STAGE=\(stage.title)")
            },
            onOutput: { _ in }
        )
        defer {
            try? FileManager.default.removeItem(at: prepared.sessionURL)
        }
        guard prepared.provenanceRows.contains(where: {
            $0.name == rootSpec.name && $0.verification == "预编译通过"
        }) else {
            throw BuilderError.validation("预编译没有生成主 Pod 来源行。")
        }

        let outcome = try await engine.package(
            session: prepared,
            outputParentURL: testOutputRoot,
            onStage: { stage in
                print("STAGE=\(stage.title)")
            },
            onOutput: { _ in }
        )
        let expectedFiles = [
            "\(rootSpec.moduleName).xcframework",
            "\(rootSpec.name).podspec",
            "DependencyProvenance.json",
            "DependencyProvenance.html",
            "THIRD_PARTY_NOTICES.md",
            "ConsumerDemo/ConsumerDemo.xcworkspace"
        ]
        for relativePath in expectedFiles {
            let path = outcome.outputURL.appendingPathComponent(relativePath).path
            guard FileManager.default.fileExists(atPath: path) else {
                throw BuilderError.validation("端到端产物缺失：\(relativePath)")
            }
        }

        print("PACKAGE_SMOKE_OK")
        print("POD=\(rootSpec.name) \(rootSpec.version)")
        print("XCFRAMEWORKS=\(outcome.xcframeworkCount)")
        print("RESOURCE_BUNDLES=\(outcome.resourceBundleCount)")
    }
}
