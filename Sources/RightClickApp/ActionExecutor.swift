import AppKit
import RightClickCore

enum ActionExecutorError: LocalizedError {
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case let .processFailed(message):
            "终端启动失败：\(message)"
        }
    }
}

@MainActor
struct ActionExecutor {
    func execute(
        _ invocation: CLIInvocation,
        terminalProfile: TerminalProfile
    ) throws {
        try run(
            invocation.command,
            directory: invocation.workingDirectory,
            terminalProfile: terminalProfile
        )
    }

    private func run(
        _ command: CLICommand,
        directory: URL,
        terminalProfile: TerminalProfile
    ) throws {
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
