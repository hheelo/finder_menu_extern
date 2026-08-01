import Foundation

public enum TerminalProfile: String, CaseIterable, Codable, Sendable {
    case terminal
    case iTerm

    /// 与 `ExternalApplication` 共用显示名，避免两处各写一份。
    public var title: String { application.title }
}

public enum CLICommand: String, CaseIterable, Codable, Hashable, Sendable {
    case codex
    case claude

    public var title: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code"
        }
    }
}

public enum ShellCommandBuilder {
    public static func command(
        _ command: CLICommand,
        in directory: URL
    ) -> String {
        "cd \(quote(directory.path)) && \(command.rawValue)"
    }

    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
