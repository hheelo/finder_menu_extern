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
                let graceDeadline = Date().addingTimeInterval(0.5)
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

enum ActionExecutorError: LocalizedError {
    case processFailed(String)
    case applicationNotFound(String)
    case commandUnsupported(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            L10n.format(
                "error.terminal_launch",
                fallback: "终端启动失败：%@",
                message
            )
        case let .applicationNotFound(name):
            L10n.format(
                "error.application_not_found",
                fallback: "未找到 %@，请先安装应用。",
                name
            )
        case let .commandUnsupported(name):
            L10n.format(
                "error.command_unsupported",
                fallback: "%@ 当前只支持打开目录，不能运行 AI CLI。请在设置中选择其他终端。",
                name
            )
        }
    }
}

@MainActor
protocol CLIExecuting {
    func openDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws

    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws

    func executeConfigured(
        _ profile: CLIProfile,
        workingDirectory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws
}

@MainActor
struct ActionExecutor: CLIExecuting {
    func openDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        switch terminalProfile {
        case .automatic, .terminal, .iTerm:
            let application = terminalProfile == .automatic
                ? ExternalApplication.terminal
                : terminalProfile.resolvedApplication
            try await open(
                [directory],
                with: application
            )
        case .warp:
            var components = URLComponents()
            components.scheme = "warp"
            components.host = "action"
            components.path = terminalWindowBehavior == .newTab
                ? "/new_tab"
                : "/new_window"
            components.queryItems = [
                URLQueryItem(name: "path", value: directory.path)
            ]
            guard let url = components.url, NSWorkspace.shared.open(url) else {
                throw ActionExecutorError.processFailed(L10n.text(
                    "error.warp_uri",
                    fallback: "无法打开 Warp URI。"
                ))
            }
        case .ghostty:
            try await launch(
                terminalProfile,
                arguments: ["--working-directory=\(directory.path)"],
                createsNewInstance: terminalWindowBehavior == .newWindow
            )
        case .wezTerm:
            var arguments = ["start", "--cwd", directory.path]
            if terminalWindowBehavior == .newTab {
                arguments.append("--new-tab")
            }
            try await launch(
                terminalProfile,
                arguments: arguments,
                createsNewInstance: terminalWindowBehavior == .newWindow
            )
        case .kitty:
            try await launch(
                terminalProfile,
                arguments: ["--directory", directory.path],
                // kitty 官方在 macOS 上建议 `open -a kitty.app -n`；没有启用
                // remote control 时不能可靠地要求已有实例创建 tab。
                createsNewInstance: true
            )
        }
    }

    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        guard terminalProfile.supportsCLIExecution else {
            throw ActionExecutorError.commandUnsupported(terminalProfile.title)
        }
        try await run(
            shellCommand: ShellCommandBuilder.command(
                invocation.command,
                in: invocation.workingDirectory
            ),
            directory: invocation.workingDirectory,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
    }

    func executeConfigured(
        _ profile: CLIProfile,
        workingDirectory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        guard profile.isValid else {
            throw ActionExecutorError.processFailed(L10n.text(
                "error.cli_configuration_invalid",
                fallback: "CLI 配置无效。"
            ))
        }
        guard terminalProfile.supportsCLIExecution else {
            throw ActionExecutorError.commandUnsupported(terminalProfile.title)
        }
        try await run(
            shellCommand: ShellCommandBuilder.command(
                executable: profile.executable,
                arguments: profile.arguments,
                in: workingDirectory
            ),
            directory: workingDirectory,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
    }

    private func run(
        shellCommand: String,
        directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        switch terminalProfile.launchStrategy {
        case .openDirectoryOnly:
            throw ActionExecutorError.commandUnsupported(terminalProfile.title)
        case .executable:
            let shellURL = UserLoginShell.resolve()
            let shellArguments = LoginShellArguments.arguments(
                shellName: shellURL.lastPathComponent,
                script: shellCommand,
                interactive: true
            )
            var arguments: [String]
            switch terminalProfile {
            case .wezTerm:
                arguments = ["start", "--cwd", directory.path]
                if terminalWindowBehavior == .newTab {
                    arguments.append("--new-tab")
                }
                arguments += ["--", shellURL.path] + shellArguments
            case .kitty:
                arguments = ["--directory", directory.path, "--", shellURL.path]
                    + shellArguments
            default:
                throw ActionExecutorError.commandUnsupported(terminalProfile.title)
            }
            try await launch(
                terminalProfile,
                arguments: arguments,
                createsNewInstance: terminalProfile == .kitty
                    || terminalWindowBehavior == .newWindow
            )
            return
        case .appleScript:
            break
        }
        let script = Self.appleScript(
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
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
                    ? L10n.format(
                        "error.osascript_status",
                        fallback: "osascript 返回状态 %lld",
                        Int64(result.terminationStatus)
                    )
                    : message
            )
        }
    }

    static func appleScript(
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) -> String {
        switch (terminalProfile, terminalWindowBehavior) {
        // 调用方保证已解析过；`.automatic` 兜底走 Terminal，
        // 它一定存在，不会对着未安装的应用发 AppleScript。
        case (.automatic, .newWindow), (.terminal, .newWindow):
            return """
            on run argv
                tell application "Terminal"
                    activate
                    do script (item 1 of argv)
                end tell
            end run
            """
        case (.automatic, .newTab), (.terminal, .newTab):
            // Terminal 的 AppleScript 字典把 tabs 暴露成只读集合，不能像
            // iTerm2 一样直接 make。用系统的新标签页快捷键，并确认标签数量
            // 确实增加后才写入命令，防止权限被拒时污染当前会话。
            let accessibilityError = appleScriptStringLiteral(L10n.text(
                "error.terminal_accessibility",
                fallback: "无法创建 Terminal 标签页；请在系统设置的隐私与安全性中允许 RightClick 使用辅助功能。"
            ))
            return """
            on run argv
                tell application "Terminal"
                    activate
                    if (count of windows) is 0 then
                        do script (item 1 of argv)
                    else
                        set targetWindow to front window
                        set oldTabCount to count of tabs of targetWindow
                        tell application "System Events" to keystroke "t" using command down
                        repeat 20 times
                            if (count of tabs of targetWindow) > oldTabCount then exit repeat
                            delay 0.05
                        end repeat
                        if (count of tabs of targetWindow) is oldTabCount then
                            error "\(accessibilityError)"
                        end if
                        do script (item 1 of argv) in selected tab of targetWindow
                    end if
                end tell
            end run
            """
        case (.iTerm, .newWindow):
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
        case (.iTerm, .newTab):
            return """
            on run argv
                tell application "iTerm2"
                    activate
                    if (count of windows) is 0 then
                        set targetWindow to (create window with default profile)
                        tell current session of targetWindow to write text (item 1 of argv)
                    else
                        tell current window
                            set targetTab to (create tab with default profile)
                            tell current session of targetTab to write text (item 1 of argv)
                        end tell
                    end if
                end tell
            end run
            """
        case (.warp, _), (.ghostty, _), (.wezTerm, _), (.kitty, _):
            // 这些 profile 不走 AppleScript；保持穷举，误调用时返回会失败的
            // 明确信息，而不是悄悄落到 Terminal。
            let message = appleScriptStringLiteral(L10n.text(
                "error.unsupported_applescript",
                fallback: "该终端不支持 AppleScript 启动策略。"
            ))
            return "error \"\(message)\""
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func open(
        _ urls: [URL],
        with application: ExternalApplication
    ) async throws {
        guard let applicationURL = installedURL(for: application) else {
            throw ActionExecutorError.applicationNotFound(application.title)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    private func launch(
        _ profile: TerminalProfile,
        arguments: [String],
        createsNewInstance: Bool
    ) async throws {
        let application = profile.resolvedApplication
        guard let applicationURL = installedURL(for: application) else {
            throw ActionExecutorError.applicationNotFound(application.title)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = createsNewInstance
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            )
        } catch {
            throw ActionExecutorError.processFailed(error.localizedDescription)
        }
    }

    private func installedURL(for application: ExternalApplication) -> URL? {
        let workspace = NSWorkspace.shared
        return application.url(
            bundleIdentifierLookup: {
                workspace.urlForApplication(withBundleIdentifier: $0)
            }
        )
    }

}
