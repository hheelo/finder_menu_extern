import AppKit
import RightClickCore

struct DiagnosticItem: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let passed: Bool
    let detail: String
}

@MainActor
enum AppDiagnostics {
    static func collect(extensionEnabled: Bool) async -> [DiagnosticItem] {
        let loginShellURL = UserLoginShell.resolve()
        async let codexPath = executablePath(
            for: .codex,
            loginShellURL: loginShellURL
        )
        async let claudePath = executablePath(
            for: .claude,
            loginShellURL: loginShellURL
        )

        let vscode = applicationURL(for: .visualStudioCode)
        let codexApp = applicationURL(for: .codex)
        let iTerm = applicationURL(for: .iTerm)

        let resolvedCodexPath = await codexPath
        let resolvedClaudePath = await claudePath
        return [
            DiagnosticItem(
                id: "extension",
                title: L10n.text("diagnostic.extension", fallback: "Finder 扩展"),
                passed: extensionEnabled,
                detail: extensionEnabled
                    ? L10n.text("diagnostic.enabled", fallback: "已启用")
                    : L10n.text("diagnostic.not_enabled", fallback: "未启用")
            ),
            DiagnosticItem(
                id: "login-shell",
                title: L10n.text("diagnostic.login_shell", fallback: "登录 Shell"),
                passed: true,
                detail: loginShellURL.path
            ),
            applicationItem(id: "vscode", title: "Visual Studio Code", url: vscode),
            applicationItem(id: "codex-app", title: "ChatGPT", url: codexApp),
            applicationItem(
                id: "iterm",
                title: L10n.format(
                    "diagnostic.optional",
                    fallback: "%@（可选）",
                    "iTerm2"
                ),
                url: iTerm
            ),
            commandItem(command: .codex, path: resolvedCodexPath),
            commandItem(command: .claude, path: resolvedClaudePath)
        ]
    }

    static func report(
        _ items: [DiagnosticItem],
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) -> String {
        let unknown = L10n.text("diagnostic.unknown", fallback: "未知")
        let version = AppVersion.displayString ?? "\(unknown) (\(unknown))"
        let missing = L10n.text("diagnostic.missing", fallback: "缺失")
        let rows = items.map {
            "[\($0.passed ? "OK" : missing)] \($0.title): \($0.detail)"
        }.joined(separator: "\n")

        let defaultTerminal = L10n.text(
            "diagnostic.default_terminal",
            fallback: "默认终端"
        )
        let terminalBehavior = L10n.text(
            "diagnostic.cli_terminal_behavior",
            fallback: "CLI 终端行为"
        )
        let cliLaunch = L10n.text(
            "diagnostic.cli_launch",
            fallback: "CLI 启动"
        )
        let cliExecutionShell = L10n.text(
            "diagnostic.cli_execution_shell",
            fallback: "CLI 执行 Shell"
        )
        let resolvedTerminal = terminalProfile.resolved {
            applicationURL(for: $0) != nil
        }
        let executionShellDetail: String
        switch resolvedTerminal.launchStrategy {
        case .appleScript:
            executionShellDetail = L10n.text(
                "diagnostic.terminal_configured_shell",
                fallback: "终端自身配置"
            )
        case .executable:
            executionShellDetail = UserLoginShell.resolve().path
        case .openDirectoryOnly:
            executionShellDetail = L10n.text(
                "diagnostic.cli_not_supported",
                fallback: "该终端不支持运行 CLI"
            )
        }
        let authenticatedOnly = L10n.text(
            "diagnostic.authenticated_only",
            fallback: "仅接受本机 Finder 扩展认证请求"
        )

        return """
        RightClick \(version)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        \(defaultTerminal): \(terminalProfile.title)
        \(terminalBehavior): \(terminalWindowBehavior.title)
        \(cliExecutionShell): \(executionShellDetail)
        \(cliLaunch): \(authenticatedOnly)

        \(rows)
        """
    }

    private static func applicationItem(
        id: String,
        title: String,
        url: URL?
    ) -> DiagnosticItem {
        DiagnosticItem(
            id: id,
            title: title,
            passed: url != nil,
            detail: url?.path ?? L10n.text(
                "diagnostic.not_found",
                fallback: "未找到"
            )
        )
    }

    private static func commandItem(
        command: CLICommand,
        path: String?
    ) -> DiagnosticItem {
        DiagnosticItem(
            id: command.rawValue,
            title: command.title,
            passed: path != nil,
            detail: path ?? L10n.text(
                "diagnostic.not_found_in_shell",
                fallback: "登录 Shell 中未找到"
            )
        )
    }

    /// 与 Finder 扩展的菜单动作共用 `ExternalApplication` 的查找规则，
    /// 避免出现「诊断说没装、菜单却能打开」这类互相矛盾的结果。
    private static func applicationURL(
        for application: ExternalApplication
    ) -> URL? {
        let workspace = NSWorkspace.shared
        return application.url(
            bundleIdentifierLookup: {
                workspace.urlForApplication(withBundleIdentifier: $0)
            }
        )
    }

    private static func executablePath(
        for command: CLICommand,
        loginShellURL: URL
    ) async -> String? {
        let shellName = loginShellURL.lastPathComponent
        let script = LoginShellArguments.executableLookupScript(
            shellName: shellName,
            command: command.rawValue
        )
        if let output = await loginShellOutput(
            shellURL: loginShellURL,
            script: script,
            interactive: false,
            timeout: 5
        ), let path = ExecutablePathParser.executablePath(in: output) {
            return path
        }

        guard LoginShellArguments.supportsInteractiveFallback(
            shellName: shellName
        ) else {
            return nil
        }

        let output = await loginShellOutput(
            shellURL: loginShellURL,
            script: script,
            interactive: true,
            timeout: 8
        )

        // 解析规则连同它的两个坑（rc 噪声、别名/函数/内建回显定义而非路径）
        // 一起放在 Core，可脱离 AppKit 测试。
        return output.flatMap {
            ExecutablePathParser.executablePath(in: $0)
        }
    }

    /// 在用户的登录 shell 中执行脚本。
    ///
    /// 必须带超时：rc 文件挂起（等待输入、慢速网络探测等）会让调用方的
    /// `isRefreshingDiagnostics` 永远停在 `true`，之后所有诊断刷新都被挡掉。
    private static func loginShellOutput(
        shellURL: URL,
        script: String,
        interactive: Bool,
        timeout: TimeInterval
    ) async -> String? {
        let arguments = LoginShellArguments.arguments(
            shellName: shellURL.lastPathComponent,
            script: script,
            interactive: interactive
        )
        guard let result = try? await ProcessRunner.run(
            executableURL: shellURL,
            arguments: arguments,
            timeout: timeout
        ), result.terminationStatus == 0 else {
            return nil
        }
        return result.standardOutput
    }

}
