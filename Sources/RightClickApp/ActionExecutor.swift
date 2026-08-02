import AppKit
import Darwin
import RightClickCore

struct ProcessRunnerResult: Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessRunnerError: LocalizedError {
    case timedOut(seconds: TimeInterval)
    case outputLimitExceeded(bytes: Int)

    var errorDescription: String? {
        switch self {
        case let .timedOut(seconds):
            "进程执行超过 \(Int(seconds)) 秒，已终止。"
        case let .outputLimitExceeded(bytes):
            "进程输出超过 \(bytes / 1_024) KB，已终止。"
        }
    }
}

/// 在后台运行短生命周期的系统工具。
///
/// 输出写入权限为 0600 的临时文件，而不是 `Pipe`：如果先等进程退出，Pipe
/// 可能被大量输出填满；如果先读到 EOF，超时后仍持有写端的子进程又可能让读取
/// 永远不返回。普通文件没有这两种互锁，超时后也能立即清理。
enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        maximumOutputBytes: Int = 1_048_576
    ) async throws -> ProcessRunnerResult {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "RightClick-Process-\(UUID().uuidString)",
                    isDirectory: true
                )
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            let outputURL = temporaryDirectory.appendingPathComponent("stdout")
            let errorURL = temporaryDirectory.appendingPathComponent("stderr")
            guard fileManager.createFile(
                atPath: outputURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ), fileManager.createFile(
                atPath: errorURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let outputHandle = try FileHandle(forWritingTo: outputURL)
            let errorHandle = try FileHandle(forWritingTo: errorURL)
            defer {
                try? outputHandle.close()
                try? errorHandle.close()
            }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputHandle
            process.standardError = errorHandle
            try process.run()

            // 轮询和退出后的复查读的是同一件事，抽出来避免两处各写一遍。
            func totalOutputSize() -> Int {
                [outputURL, errorURL].reduce(0) { total, url in
                    let attributes = try? fileManager.attributesOfItem(
                        atPath: url.path
                    )
                    let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                    return total + size
                }
            }

            let deadline = timeout.map { Date().addingTimeInterval($0) }
            var didTimeOut = false
            var wasCancelled = false
            var exceededOutputLimit = false
            // 短命令要尽快返回，所以从 10ms 起步；但等待用户响应自动化授权
            // 可能长达一分钟，一直按 10ms 轮询就是每秒 100 次唤醒、200 次
            // stat。逐步退避到 100ms：快命令的延迟几乎不变，长等待的开销降一个
            // 数量级。
            var pollInterval = Duration.milliseconds(10)
            let maximumPollInterval = Duration.milliseconds(100)
            while process.isRunning {
                // 取消和超时是两回事：混在一起时，未设超时的调用被取消会报出
                // 「进程执行超过 0 秒」这种自相矛盾的提示。
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
                if deadline.map({ Date() >= $0 }) == true {
                    didTimeOut = true
                    break
                }
                if totalOutputSize() > maximumOutputBytes {
                    exceededOutputLimit = true
                    break
                }
                try? await Task.sleep(for: pollInterval)
                pollInterval = min(pollInterval * 2, maximumPollInterval)
            }

            if didTimeOut || wasCancelled || exceededOutputLimit {
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < graceDeadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }

            process.waitUntilExit()
            // 最后一次轮询到进程退出之间仍可能写出内容，退出后再复查一次。
            if totalOutputSize() > maximumOutputBytes {
                exceededOutputLimit = true
            }
            // 用 `try?`：这里的收尾失败不该盖掉下面真正要报的超时/超限原因。
            // 句柄的兜底关闭仍由前面的 defer 负责（重复关闭是幂等的）。
            try? outputHandle.synchronize()
            try? errorHandle.synchronize()
            try? outputHandle.close()
            try? errorHandle.close()

            if wasCancelled {
                throw CancellationError()
            }
            if didTimeOut {
                throw ProcessRunnerError.timedOut(seconds: timeout ?? 0)
            }
            if exceededOutputLimit {
                throw ProcessRunnerError.outputLimitExceeded(
                    bytes: maximumOutputBytes
                )
            }

            return ProcessRunnerResult(
                terminationStatus: process.terminationStatus,
                standardOutput: String(
                    decoding: try Data(contentsOf: outputURL),
                    as: UTF8.self
                ),
                standardError: String(
                    decoding: try Data(contentsOf: errorURL),
                    as: UTF8.self
                )
            )
        }.value
    }
}

enum ActionExecutorError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            "终端启动失败：\(message)"
        }
    }
}

@MainActor
struct ActionExecutor {
    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile
    ) async throws {
        try await run(
            invocation.command,
            directory: invocation.workingDirectory,
            terminalProfile: terminalProfile
        )
    }

    private func run(
        _ command: CLICommand,
        directory: URL,
        terminalProfile: TerminalProfile
    ) async throws {
        let shellCommand = ShellCommandBuilder.command(command, in: directory)
        let script = appleScript(
            terminalProfile: terminalProfile
        )
        let result: ProcessRunnerResult
        do {
            // 首次自动化授权需要给用户足够时间响应，但不能无限占住任务。
            result = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script, "--", shellCommand],
                timeout: 60
            )
        } catch {
            throw ActionExecutorError.processFailed(error.localizedDescription)
        }

        guard result.terminationStatus == 0 else {
            let message = result.standardError
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ActionExecutorError.processFailed(
                message.isEmpty
                    ? "osascript 返回状态 \(result.terminationStatus)"
                    : message
            )
        }
    }

    private func appleScript(
        terminalProfile: TerminalProfile
    ) -> String {
        switch terminalProfile {
        // 调用方保证已解析过；`.automatic` 兜底走 Terminal，
        // 它一定存在，不会对着未安装的应用发 AppleScript。
        case .automatic, .terminal:
            return """
            on run argv
                tell application "Terminal"
                    activate
                    do script (item 1 of argv)
                end tell
            end run
            """
        case .iTerm:
            // iTerm2 的 `command` 参数不经过 shell，直接把
            // `cd '...' && codex` 交给它会失败，连窗口都建不起来
            // （实测返回 missing value）。所以先建一个正常的 shell 会话，
            // 再把命令写进去——与 Terminal 的 `do script` 语义一致。
            return """
            on run argv
                tell application "iTerm2"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text (item 1 of argv)
                end tell
            end run
            """
        }
    }
}
