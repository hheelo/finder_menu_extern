import AppKit
import RightClickCore

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
    private static let automationAuthorizationTimeout: TimeInterval = 60
    private static let terminalTabCreationAttempts = 20
    private static let terminalTabCreationDelay = 0.05

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
                executableURL: AppConstants.osaScriptURL,
                arguments: ["-e", script, "--", shellCommand],
                timeout: Self.automationAuthorizationTimeout
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
                        repeat \(Self.terminalTabCreationAttempts) times
                            if (count of tabs of targetWindow) > oldTabCount then exit repeat
                            delay \(Self.terminalTabCreationDelay)
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
