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
        let loginShellURL = resolvedLoginShellURL()
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
                title: "Finder 扩展",
                passed: extensionEnabled,
                detail: extensionEnabled ? "已启用" : "未启用"
            ),
            DiagnosticItem(
                id: "login-shell",
                title: "登录 Shell",
                passed: true,
                detail: loginShellURL.path
            ),
            applicationItem(id: "vscode", title: "Visual Studio Code", url: vscode),
            applicationItem(id: "codex-app", title: "ChatGPT", url: codexApp),
            applicationItem(id: "iterm", title: "iTerm2（可选）", url: iTerm),
            commandItem(command: .codex, path: resolvedCodexPath),
            commandItem(command: .claude, path: resolvedClaudePath)
        ]
    }

    static func report(
        _ items: [DiagnosticItem],
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) -> String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "未知"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "未知"
        let rows = items.map {
            "[\($0.passed ? "OK" : "缺失")] \($0.title)：\($0.detail)"
        }.joined(separator: "\n")

        return """
        RightClick \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        默认终端：\(terminalProfile.title)
        CLI 终端行为：\(terminalWindowBehavior.title)
        CLI 启动：仅接受本机 Finder 扩展认证请求

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
            detail: url?.path ?? "未找到"
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
            detail: path ?? "登录 Shell 中未找到"
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

    /// `SHELL` 可能被继承环境污染，只接受真实存在的绝对可执行路径。
    /// 取不到时回退 macOS 默认的 zsh。
    private static func resolvedLoginShellURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        let fallback = URL(fileURLWithPath: "/bin/zsh")
        guard let path = environment["SHELL"], path.hasPrefix("/"),
              fileManager.isExecutableFile(atPath: path) else {
            return fallback
        }
        return URL(fileURLWithPath: path)
    }
}
