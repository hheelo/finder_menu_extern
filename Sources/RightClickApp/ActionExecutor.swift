import AppKit
import RightClickAppLogic
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

    func openDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) async throws {
        guard let plan = TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        ) else {
            throw ActionExecutorError.processFailed(L10n.text(
                "error.warp_uri",
                fallback: "无法打开终端 URI。"
            ))
        }
        try await execute(plan)
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
        guard let plan = TerminalLaunchPlan.runningCommand(
            shellCommand,
            in: directory,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior,
            loginShellURL: UserLoginShell.resolve()
        ) else {
            throw ActionExecutorError.commandUnsupported(terminalProfile.title)
        }
        try await execute(plan)
    }

    private func execute(_ plan: TerminalLaunchPlan) async throws {
        switch plan {
        case let .openFiles(application, urls):
            try await open(urls, with: application)
        case let .openURL(url):
            guard NSWorkspace.shared.open(url) else {
                throw ActionExecutorError.processFailed(L10n.text(
                    "error.warp_uri",
                    fallback: "无法打开终端 URI。"
                ))
            }
        case let .launchApplication(application, arguments, createsNewInstance):
            try await launch(
                application,
                arguments: arguments,
                createsNewInstance: createsNewInstance
            )
        case let .runAppleScript(script, argument):
            let result: ProcessRunnerResult
            do {
                result = try await ProcessRunner.run(
                    executableURL: AppConstants.osaScriptURL,
                    arguments: ["-e", script, "--", argument],
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
        _ application: ExternalApplication,
        arguments: [String],
        createsNewInstance: Bool
    ) async throws {
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
