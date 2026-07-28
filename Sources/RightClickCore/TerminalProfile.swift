import Foundation

public enum TerminalProfile: String, CaseIterable, Codable, Sendable {
    case terminal
    case iTerm

    public var title: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm2"
        }
    }
}

public enum CLICommand: String, Codable, Sendable {
    case codex
    case claude
}

public enum ShellCommandBuilder {
    public static func command(_ command: CLICommand, in directory: URL) -> String {
        "cd \(quote(directory.path)) && \(command.rawValue)"
    }

    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
