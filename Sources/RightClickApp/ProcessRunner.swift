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
            L10n.format(
                "error.process_timeout",
                fallback: "进程执行超过 %lld 秒，已终止。",
                Int64(seconds)
            )
        case let .outputLimitExceeded(bytes):
            L10n.format(
                "error.output_limit",
                fallback: "进程输出超过 %lld KB，已终止。",
                Int64(bytes / 1_024)
            )
        }
    }
}

/// 在后台运行短生命周期的系统工具。
///
/// 输出写入权限为 0600 的临时文件，而不是 `Pipe`：如果先等进程退出，Pipe
/// 可能被大量输出填满；如果先读到 EOF，超时后仍持有写端的子进程又可能让读取
/// 永远不返回。普通文件没有这两种互锁，超时后也能立即清理。
enum ProcessRunner {
    private static let forceTerminationWait: TimeInterval = 2
    private static let terminationGracePeriod: TimeInterval = 0.5

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval? = nil,
        maximumOutputBytes: Int = 1_048_576
    ) async throws -> ProcessRunnerResult {
        let task = Task.detached(priority: .utility) {
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
            func fileSize(at url: URL) -> Int {
                let attributes = try? fileManager.attributesOfItem(
                    atPath: url.path
                )
                return (attributes?[.size] as? NSNumber)?.intValue ?? 0
            }

            func totalOutputSize() -> Int {
                fileSize(at: outputURL) + fileSize(at: errorURL)
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
            var tickCount = 0
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
                tickCount += 1
                if tickCount.isMultiple(of: 10),
                   totalOutputSize() > maximumOutputBytes {
                    exceededOutputLimit = true
                    break
                }
                try? await Task.sleep(for: pollInterval)
                pollInterval = min(pollInterval * 2, maximumPollInterval)
            }

            if didTimeOut || wasCancelled || exceededOutputLimit {
                process.terminate()
                let graceDeadline = Date().addingTimeInterval(
                    terminationGracePeriod
                )
                while process.isRunning && Date() < graceDeadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = await waitUntilStopped(
                        deadline: Date().addingTimeInterval(
                            forceTerminationWait
                        ),
                        isRunning: { process.isRunning }
                    )
                }
            }

            // 正常退出时不再调用 `waitUntilExit()`：macOS 26 的 Foundation 会
            // 偶发丢失已经发生的退出通知，导致无子进程可等却永久阻塞。强杀后
            // 若状态仍未翻转也会在有界等待后到这里，但三个原因标志保证后面不会
            // 读取尚不可用的 terminationStatus。
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
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            // detached task 不会继承调用方稍后发生的取消；显式转发后，内部轮询
            // 才能终止子进程并清理私有临时目录。
            task.cancel()
        }
    }

    /// `Process.isRunning` 极少数情况下不会在强杀后翻转。调用方只需要一个
    /// 有界等待；超时后仍按原始的取消、超时或输出超限原因返回。
    static func waitUntilStopped(
        deadline: Date,
        isRunning: () -> Bool
    ) async -> Bool {
        while isRunning() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return !isRunning()
    }
}
