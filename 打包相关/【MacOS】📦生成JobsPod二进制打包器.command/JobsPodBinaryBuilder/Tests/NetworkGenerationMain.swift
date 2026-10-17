//
//  NetworkGenerationMain.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年10月17日，星期六.
//

import Foundation

// 只生成临时工程与资源，不启动 CocoaPods 或 Xcode 构建。
let resourceRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fixtureRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fileManager = FileManager.default

func record(_ name: String, version: String, kind: PodSourceKind, path: URL) -> PodSpecRecord {
    return PodSpecRecord(
        name: name,
        version: version,
        moduleName: name,
        podspecPath: path.appendingPathComponent("\(name).podspec.json").path,
        directoryPath: path.path,
        sourceKind: kind,
        license: "MIT",
        sourceURL: "https://private.example.invalid/\(name).git",
        summary: "Offline fixture",
        dependencies: [],
        frameworks: [],
        libraries: [],
        resourceBundleNames: []
    )
}

let root = record("JobsFixture", version: "1.2.3", kind: .localJobs, path: fixtureRoot.appendingPathComponent("Source With Space"))
let remote = record("AMPopTip", version: "4.12.0", kind: .remote, path: fixtureRoot.appendingPathComponent("Remote"))
let importedPath = fixtureRoot.appendingPathComponent("ReadOnlyPrivateSource")
try fileManager.createDirectory(at: importedPath, withIntermediateDirectories: true)
try "private-source-original".write(to: importedPath.appendingPathComponent("Source.txt"), atomically: true, encoding: .utf8)
try "{\"name\":\"PrivateFixture\",\"version\":\"2.4.0\",\"source\":{\"git\":\"https://private.example.invalid/PrivateFixture.git\"}}".write(
    to: importedPath.appendingPathComponent("PrivateFixture.podspec.json"), atomically: true, encoding: .utf8
)
let imported = record("PrivateFixture", version: "2.4.0", kind: .projectPods, path: importedPath)

try ProjectGenerator.writePackagingWorkspace(
    at: fixtureRoot.appendingPathComponent("Packaging"),
    rootSpec: root,
    allSpecs: [root, remote, imported],
    cocoaPodsResourceRoot: resourceRoot
)
try ProjectGenerator.writeConsumerDemo(
    at: fixtureRoot.appendingPathComponent("Consumer"),
    rootSpec: root,
    binarySDKURL: fixtureRoot.appendingPathComponent("Binary SDK"),
    cocoaPodsResourceRoot: resourceRoot
)

let missingRoot = fixtureRoot.appendingPathComponent("MissingResources")
do {
    _ = try ProjectGenerator.writeCocoaPodsSupport(at: fixtureRoot, resourceRoot: missingRoot)
    fatalError("缺失资源未阻断生成")
} catch BuilderError.environment {
    print("MISSING_RESOURCES_BLOCKED")
}
let occupied = fixtureRoot.appendingPathComponent("Packaging/ScriptsByPods/【MacOS】🌐CocoaPods网络适配.command/README.md")
try "keep-user-content".write(to: occupied, atomically: true, encoding: .utf8)
do {
    _ = try ProjectGenerator.writeCocoaPodsSupport(at: fixtureRoot.appendingPathComponent("Packaging"), resourceRoot: resourceRoot)
    fatalError("已有资源未阻止覆盖")
} catch BuilderError.validation {
    print("EXISTING_RESOURCES_PRESERVED")
}
print("OFFLINE_GENERATION_OK")
