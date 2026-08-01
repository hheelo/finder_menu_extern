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
        terminalProfile: TerminalProfile,
        confirmationEnabled: Bool
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
        启动前确认：\(confirmationEnabled ? "开启" : "关闭")

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

        // 登录 shell 会 source 用户的 rc 文件，其中的横幅/提示同样会写到
        // stdout，因此不能把整段输出当成路径，只取最后一行非空内容。
        let path = output?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return path.isEmpty ? nil : path
    }

    /// 在用户的登录 shell 中执行脚本。
    ///
    /// 必须带超时：rc 文件挂起（等待输入、慢速网络探测等）会让调用方的
    /// `isRefreshingDiagnostics` 永远停在 `true`，之后所有诊断刷新都被挡掉。
    private static func loginShellOutput(
        script: String,
        timeout: Duration = .seconds(5)
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // 保留 -i：很多用户把 PATH 写在只有交互式 shell 才加载的 .zshrc 里。
            process.arguments = ["-lic", script]
            // 交互式 shell 不应该从宿主 App 继承 stdin 并阻塞在读取上。
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let watchdog = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                ProcessBox(process).terminate()
            }
            defer { watchdog.cancel() }

            // 先读到 EOF 再等退出：rc 文件的输出可能填满管道缓冲区，
            // 那时先 waitUntilExit 会双方互等而死锁。
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

/// `Process` 不是 `Sendable`，但从其他线程调用 `terminate()` 是安全的，
/// 这里只为把超时看守跨并发域传递而做最小封装。
private final class ProcessBox: @unchecked Sendable {
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
