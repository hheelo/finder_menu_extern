import AppKit
import RightClickCore

enum ActionExecutorError: LocalizedError {
    case applicationNotFound(String)
    case missingWorkingDirectory
    case processFailed(String)
    case unsupportedAction

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(name):
            "未找到 \(name)，请先安装应用。"
        case .missingWorkingDirectory:
            "无法确定要打开的工作目录。"
        case let .processFailed(message):
            "终端启动失败：\(message)"
        case .unsupportedAction:
            "宿主 App 收到了不应由它处理的操作。"
        }
    }
}

@MainActor
struct ActionExecutor {
    private let workspace = NSWorkspace.shared

    func execute(
        _ request: ActionRequest,
        terminalProfile: TerminalProfile
    ) throws {
        switch request.action {
        case .openInVSCode:
            try open(
                request.selectedURLs,
                bundleIdentifiers: ["com.microsoft.VSCode"],
                displayName: "Visual Studio Code"
            )
        case .openInCodex:
            try open(
                request.selectedURLs,
                bundleIdentifiers: ["com.openai.codex"],
                displayName: "Codex"
            )
        case .runCodexCLI:
            try run(.codex, request: request, terminalProfile: terminalProfile)
        case .runClaudeCode:
            try run(.claude, request: request, terminalProfile: terminalProfile)
        case .copyPath, .copyFilename, .createFile:
            throw ActionExecutorError.unsupportedAction
        }
    }

    private func open(
        _ urls: [URL],
        bundleIdentifiers: [String],
        displayName: String
    ) throws {
        guard let appURL = bundleIdentifiers.lazy.compactMap({
            workspace.urlForApplication(withBundleIdentifier: $0)
        }).first else {
            throw ActionExecutorError.applicationNotFound(displayName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(
            urls,
            withApplicationAt: appURL,
            configuration: configuration
        )
    }

    private func run(
        _ command: CLICommand,
        request: ActionRequest,
        terminalProfile: TerminalProfile
    ) throws {
        guard let directory = SelectionContext(
            selectedURLs: request.selectedURLs,
            targetedURL: request.targetedURL
        ).workingDirectory else {
            throw ActionExecutorError.missingWorkingDirectory
        }

        let shellCommand = ShellCommandBuilder.command(command, in: directory)
        let script = appleScript(
            terminalProfile: terminalProfile,
            shellCommand: shellCommand
        )
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
            throw ActionExecutorError.processFailed(message)
        }
    }

    private func appleScript(
        terminalProfile: TerminalProfile,
        shellCommand: String
    ) -> String {
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        switch terminalProfile {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        case .iTerm:
            return """
            tell application "iTerm2"
                activate
                create window with default profile command "\(escaped)"
            end tell
            """
        }
    }
}
