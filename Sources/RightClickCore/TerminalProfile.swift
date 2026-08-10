import Foundation

public enum TerminalProfile: String, CaseIterable, Codable, Sendable {
    /// 默认值：装了 iTerm2 就用 iTerm2，否则回退到系统自带的 Terminal。
    case automatic
    case terminal
    case iTerm
    case warp
    case ghostty
    case wezTerm
    case kitty

    public var title: String {
        switch self {
        case .automatic:
            L10n.text("terminal.automatic", fallback: "自动（优先 iTerm2）")
        // 与 `ExternalApplication` 共用显示名，避免两处各写一份。
        case .terminal, .iTerm, .warp, .ghostty, .wezTerm, .kitty:
            resolvedApplication.title
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
        case .warp, .ghostty, .wezTerm, .kitty:
            return isInstalled(resolvedApplication) ? self : .terminal
        }
    }

    /// 解析后对应的 App。`.automatic` 未解析时按优先项给出，仅用于展示。
    public var resolvedApplication: ExternalApplication {
        switch self {
        case .terminal: .terminal
        case .automatic, .iTerm: .iTerm
        case .warp: .warp
        case .ghostty: .ghostty
        case .wezTerm: .wezTerm
        case .kitty: .kitty
        }
    }

    /// 可供用户显式选择的项，`.automatic` 在最前面作为默认。
    public static var selectableCases: [TerminalProfile] { allCases }
}

public enum TerminalLaunchStrategy: Equatable, Sendable {
    /// Terminal 与 iTerm2：支持 AppleScript 写入命令。
    case appleScript
    /// Warp / Ghostty：当前只使用官方稳定的按目录启动能力。
    case openDirectoryOnly
    /// App bundle 内可执行文件支持 cwd 与待运行程序参数。
    case executable(relativePath: String)
}

public extension TerminalProfile {
    var launchStrategy: TerminalLaunchStrategy {
        switch self {
        case .automatic, .terminal, .iTerm:
            .appleScript
        case .warp, .ghostty:
            .openDirectoryOnly
        case .wezTerm:
            .executable(relativePath: "Contents/MacOS/wezterm")
        case .kitty:
            .executable(relativePath: "Contents/MacOS/kitty")
        }
    }

    var supportsCLIExecution: Bool {
        launchStrategy != .openDirectoryOnly
    }
}

public enum TerminalWindowBehavior: String, CaseIterable, Codable, Sendable {
    case newTab
    case newWindow

    public var title: String {
        switch self {
        case .newTab: L10n.text("terminal.new_tab", fallback: "新标签页")
        case .newWindow: L10n.text("terminal.new_window", fallback: "新窗口")
        }
    }
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

    public static func command(
        executable: String,
        arguments: [String],
        in directory: URL
    ) -> String {
        let invocation = ([executable] + arguments).map(quote).joined(separator: " ")
        return "cd \(quote(directory.path)) && \(invocation)"
    }

    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
