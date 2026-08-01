import Foundation

public enum TerminalProfile: String, CaseIterable, Codable, Sendable {
    /// 默认值：装了 iTerm2 就用 iTerm2，否则回退到系统自带的 Terminal。
    case automatic
    case terminal
    case iTerm

    public var title: String {
        switch self {
        case .automatic: "自动（优先 iTerm2）"
        // 与 `ExternalApplication` 共用显示名，避免两处各写一份。
        case .terminal, .iTerm: resolvedApplication.title
        }
    }

    /// 解析成一个确定存在的终端。
    ///
    /// 除了 `.automatic` 的择优，显式选中 iTerm2 却没安装时也要回退——
    /// 否则 AppleScript 会对着不存在的应用报错，而用户无从判断原因。
    ///
    /// `isInstalled` 由调用方注入：查询已安装应用需要 AppKit，而 Core 不依赖它。
    public func resolved(
        isInstalled: (ExternalApplication) -> Bool
    ) -> TerminalProfile {
        switch self {
        case .terminal:
            return .terminal
        case .automatic, .iTerm:
            return isInstalled(.iTerm) ? .iTerm : .terminal
        }
    }

    /// 解析后对应的 App。`.automatic` 未解析时按优先项给出，仅用于展示。
    public var resolvedApplication: ExternalApplication {
        switch self {
        case .terminal: .terminal
        case .automatic, .iTerm: .iTerm
        }
    }

    /// 可供用户显式选择的项，`.automatic` 在最前面作为默认。
    public static var selectableCases: [TerminalProfile] { allCases }
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
