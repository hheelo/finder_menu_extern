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
    case applicationNotFound(String)
    case commandUnsupported(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            "终端启动失败：\(message)"
        case let .applicationNotFound(name):
            "未找到 \(name)，请先安装应用。"
        case let .commandUnsupported(name):
            "\(name) 当前只支持打开目录，不能运行 AI CLI。请在设置中选择其他终端。"
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
                throw ActionExecutorError.processFailed("无法打开 Warp URI。")
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
            throw ActionExecutorError.processFailed("CLI 配置无效。")
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
            let shellURL = Self.loginShellURL()
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
                    ? "osascript 返回状态 \(result.terminationStatus)"
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
                            error "无法创建 Terminal 标签页；请在系统设置的隐私与安全性中允许 RightClick 使用辅助功能。"
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
            return "error \"该终端不支持 AppleScript 启动策略。\""
        }
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

    private static func loginShellURL() -> URL {
        guard let user = getpwuid(getuid()),
              let shell = user.pointee.pw_shell,
              shell.pointee != 0 else {
            return URL(fileURLWithPath: "/bin/zsh")
        }
        return URL(fileURLWithPath: String(cString: shell))
    }
}
