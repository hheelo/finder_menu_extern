import AppKit
import RightClickCore

struct DiagnosticItem: Identifiable, Sendable {
    let id: String
    let title: String
    let passed: Bool
    let detail: String
}

@MainActor
enum AppDiagnostics {
    static func collect(extensionEnabled: Bool) async -> [DiagnosticItem] {
        async let codexPath = executablePath(for: .codex)
        async let claudePath = executablePath(for: .claude)

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
            applicationItem(id: "vscode", title: "Visual Studio Code", url: vscode),
            applicationItem(id: "codex-app", title: "Codex App", url: codexApp),
            applicationItem(id: "iterm", title: "iTerm2（可选）", url: iTerm),
            commandItem(command: .codex, path: resolvedCodexPath),
            commandItem(command: .claude, path: resolvedClaudePath)
        ]
    }

    static func report(
        _ items: [DiagnosticItem],
        terminalProfile: TerminalProfile
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
        for command: CLICommand
    ) async -> String? {
        let output = await loginShellOutput(
            script: "command -v -- \(command.rawValue) 2>/dev/null"
        )

        // 解析规则连同它的两个坑（rc 噪声、别名/函数/内建回显定义而非路径）
        // 一起放在 Core，可脱离 AppKit 测试。
        return output.flatMap(ExecutablePathParser.executablePath(in:))
    }

    /// 在用户的登录 shell 中执行脚本。
    ///
    /// 必须带超时：rc 文件挂起（等待输入、慢速网络探测等）会让调用方的
    /// `isRefreshingDiagnostics` 永远停在 `true`，之后所有诊断刷新都被挡掉。
    private static func loginShellOutput(
        script: String,
        timeout: TimeInterval = 5
    ) async -> String? {
        // 保留 -i：很多用户把 PATH 写在只有交互式 shell 才加载的 .zshrc 里。
        // ProcessRunner 用普通临时文件承接输出，即使 rc 脚本派生的子进程继续持有
        // stdout，超时也不再等待管道 EOF。
        guard let result = try? await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lic", script],
            timeout: timeout
        ), result.terminationStatus == 0 else {
            return nil
        }
        return result.standardOutput
    }
}
