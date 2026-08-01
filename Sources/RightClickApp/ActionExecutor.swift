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
    ) async throws {
        try await run(
            invocation.command,
            directory: invocation.workingDirectory,
            terminalProfile: terminalProfile
        )
    }

    private func run(
        _ command: CLICommand,
        directory: URL,
        terminalProfile: TerminalProfile
    ) async throws {
        let shellCommand = ShellCommandBuilder.command(command, in: directory)
        let script = appleScript(
            terminalProfile: terminalProfile
        )
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, "--", shellCommand]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ActionExecutorError.processFailed(
                    message.isEmpty ? "osascript 返回状态 \(process.terminationStatus)" : message
                )
            }
        }.value
    }

    private func appleScript(
        terminalProfile: TerminalProfile
    ) -> String {
        switch terminalProfile {
        // 调用方保证已解析过；`.automatic` 兜底走 Terminal，
        // 它一定存在，不会对着未安装的应用发 AppleScript。
        case .automatic, .terminal:
            return """
            on run argv
                tell application "Terminal"
                    activate
                    do script (item 1 of argv)
                end tell
            end run
            """
        case .iTerm:
            return """
            on run argv
                tell application "iTerm2"
                    activate
                    create window with default profile command (item 1 of argv)
                end tell
            end run
            """
        }
    }
}
