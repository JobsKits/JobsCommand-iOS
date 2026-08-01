//
//  CommandRunner.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import Foundation

private final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var output = ""
    private var isFinished = false

    // 线程安全地累计命令输出。
    func append(_ text: String) {
        lock.lock()
        output.append(text)
        lock.unlock()
    }

    // 读取当前累计的完整输出。
    func snapshot() -> String {
        lock.lock()
        let value = output
        lock.unlock()
        return value
    }

    // 保证 continuation 只结束一次。
    func beginFinishing() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isFinished == false else { return false }
        isFinished = true
        return true
    }
}

final class CommandRunner {
    private let stateLock = NSLock()
    private var currentProcess: Process?
    private var cancellationRequested = false

    // 执行外部命令，并实时回传标准输出和错误输出。
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        onOutput: @escaping (String) -> Void
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let capture = CommandCapture()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, newValue in newValue }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.isEmpty == false else { return }
                let text = String(decoding: data, as: UTF8.self)
                capture.append(text)
                onOutput(text)
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                if remainingData.isEmpty == false {
                    let remainingText = String(decoding: remainingData, as: UTF8.self)
                    capture.append(remainingText)
                    onOutput(remainingText)
                }

                self?.stateLock.lock()
                let wasCancelled = self?.cancellationRequested ?? false
                self?.currentProcess = nil
                self?.stateLock.unlock()

                let finalOutput = capture.snapshot()
                guard capture.beginFinishing() else { return }
                if wasCancelled {
                    continuation.resume(throwing: BuilderError.cancelled)
                } else {
                    continuation.resume(returning: CommandResult(
                        exitCode: terminatedProcess.terminationStatus,
                        output: finalOutput
                    ))
                }
            }

            stateLock.lock()
            cancellationRequested = false
            currentProcess = process
            stateLock.unlock()

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                stateLock.lock()
                currentProcess = nil
                stateLock.unlock()
                guard capture.beginFinishing() else { return }
                continuation.resume(throwing: error)
            }
        }
    }

    // 请求中断当前 CocoaPods 或 Xcode 子进程。
    func cancel() {
        stateLock.lock()
        cancellationRequested = true
        let process = currentProcess
        stateLock.unlock()

        guard let process, process.isRunning else { return }
        process.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}

enum ToolLocator {
    // 查找 macOS 常见安装位置中的可执行文件。
    static func executable(named name: String, candidates: [String] = []) -> String? {
        let fileManager = FileManager.default
        let allCandidates = candidates + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)"
        ]
        if let match = allCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return match
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(name)"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.isEmpty == false, fileManager.isExecutableFile(atPath: path) else { return nil }
        return path
    }
}
