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

        let workspace = NSWorkspace.shared
        let vscode = applicationURL(
            bundleIdentifiers: ["com.microsoft.VSCode"],
            names: ["Visual Studio Code"],
            workspace: workspace
        )
        let codexApp = applicationURL(
            bundleIdentifiers: ["com.openai.codex"],
            names: ["Codex"],
            workspace: workspace
        )
        let iTerm = applicationURL(
            bundleIdentifiers: ["com.googlecode.iterm2"],
            names: ["iTerm", "iTerm2"],
            workspace: workspace
        )

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

    private static func applicationURL(
        bundleIdentifiers: [String],
        names: [String],
        workspace: NSWorkspace
    ) -> URL? {
        let installed = bundleIdentifiers.lazy.compactMap {
            workspace.urlForApplication(withBundleIdentifier: $0)
        }.first
        if let installed {
            return installed
        }

        return names.lazy
            .flatMap { name in
                [
                    URL(fileURLWithPath: "/Applications/\(name).app"),
                    FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Applications/\(name).app")
                ]
            }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func executablePath(
        for command: CLICommand
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [
                "-lic",
                "command -v -- \(command.rawValue) 2>/dev/null"
            ]
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            } catch {
                return nil
            }
        }.value
    }
}
