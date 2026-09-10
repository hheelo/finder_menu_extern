import Foundation
import RightClickCore

/// A testable description of one terminal launch. It contains no AppKit calls;
/// the host app executes the resulting operation at its system boundary.
public enum TerminalLaunchPlan: Equatable, Sendable {
    case openFiles(application: ExternalApplication, urls: [URL])
    case openURL(URL)
    case launchApplication(
        application: ExternalApplication,
        arguments: [String],
        createsNewInstance: Bool
    )
    case runAppleScript(script: String, argument: String)

    public static func openingDirectory(
        _ directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) -> TerminalLaunchPlan? {
        switch terminalProfile {
        case .automatic, .terminal, .iTerm:
            let application = terminalProfile == .automatic
                ? ExternalApplication.terminal
                : terminalProfile.resolvedApplication
            return .openFiles(application: application, urls: [directory])
        case .warp:
            var components = URLComponents()
            components.scheme = "warp"
            components.host = "action"
            components.path = terminalWindowBehavior == .newTab
                ? "/new_tab"
                : "/new_window"
            components.queryItems = [
                URLQueryItem(name: "path", value: directory.path)
            ]
            return components.url.map(TerminalLaunchPlan.openURL)
        case .ghostty:
            return .launchApplication(
                application: terminalProfile.resolvedApplication,
                arguments: ["--working-directory=\(directory.path)"],
                createsNewInstance: terminalWindowBehavior == .newWindow
            )
        case .wezTerm:
            var arguments = ["start", "--cwd", directory.path]
            if terminalWindowBehavior == .newTab {
                arguments.append("--new-tab")
            }
            return .launchApplication(
                application: terminalProfile.resolvedApplication,
                arguments: arguments,
                createsNewInstance: terminalWindowBehavior == .newWindow
            )
        case .kitty:
            return .launchApplication(
                application: terminalProfile.resolvedApplication,
                arguments: ["--directory", directory.path],
                // kitty recommends `open -a kitty.app -n` on macOS. Without
                // remote control it cannot reliably add a tab to an instance.
                createsNewInstance: true
            )
        }
    }

    public static func runningCommand(
        _ shellCommand: String,
        in directory: URL,
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior,
        loginShellURL: URL
    ) -> TerminalLaunchPlan? {
        switch terminalProfile.launchStrategy {
        case .openDirectoryOnly:
            return nil
        case .executable:
            let shellArguments = LoginShellArguments.arguments(
                shellName: loginShellURL.lastPathComponent,
                script: shellCommand,
                interactive: true
            )
            let arguments: [String]
            let createsNewInstance: Bool
            switch terminalProfile {
            case .wezTerm:
                var wezTermArguments = ["start", "--cwd", directory.path]
                if terminalWindowBehavior == .newTab {
                    wezTermArguments.append("--new-tab")
                }
                arguments = wezTermArguments + ["--", loginShellURL.path]
                    + shellArguments
                createsNewInstance = terminalWindowBehavior == .newWindow
            case .kitty:
                arguments = [
                    "--directory", directory.path, "--", loginShellURL.path
                ] + shellArguments
                createsNewInstance = true
            default:
                return nil
            }
            return .launchApplication(
                application: terminalProfile.resolvedApplication,
                arguments: arguments,
                createsNewInstance: createsNewInstance
            )
        case .appleScript:
            return .runAppleScript(
                script: appleScript(
                    terminalProfile: terminalProfile,
                    terminalWindowBehavior: terminalWindowBehavior
                ),
                argument: shellCommand
            )
        }
    }

    public static func appleScript(
        terminalProfile: TerminalProfile,
        terminalWindowBehavior: TerminalWindowBehavior
    ) -> String {
        switch (terminalProfile, terminalWindowBehavior) {
        case (.automatic, .newWindow), (.terminal, .newWindow):
            return """
            on run argv
                tell application "Terminal"
                    activate
                    do script (item 1 of argv)
                end tell
            end run
            """
        case (.automatic, .newTab), (.terminal, .newTab):
            let accessibilityError = appleScriptStringLiteral(L10n.text(
                "error.terminal_accessibility",
                fallback: "无法创建 Terminal 标签页；请在系统设置的隐私与安全性中允许 RightClick 使用辅助功能。"
            ))
            return """
            on run argv
                tell application "Terminal"
                    activate
                    if (count of windows) is 0 then
                        do script (item 1 of argv)
                    else
                        set targetWindow to front window
                        set oldTabCount to count of tabs of targetWindow
                        tell application "System Events" to keystroke "t" using command down
                        repeat 20 times
                            if (count of tabs of targetWindow) > oldTabCount then exit repeat
                            delay 0.05
                        end repeat
                        if (count of tabs of targetWindow) is oldTabCount then
                            error "\(accessibilityError)"
                        end if
                        do script (item 1 of argv) in selected tab of targetWindow
                    end if
                end tell
            end run
            """
        case (.iTerm, .newWindow):
            return """
            on run argv
                tell application "iTerm2"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text (item 1 of argv)
                end tell
            end run
            """
        case (.iTerm, .newTab):
            return """
            on run argv
                tell application "iTerm2"
                    activate
                    if (count of windows) is 0 then
                        set targetWindow to (create window with default profile)
                        tell current session of targetWindow to write text (item 1 of argv)
                    else
                        tell current window
                            set targetTab to (create tab with default profile)
                            tell current session of targetTab to write text (item 1 of argv)
                        end tell
                    end if
                end tell
            end run
            """
        case (.warp, _), (.ghostty, _), (.wezTerm, _), (.kitty, _):
            let message = appleScriptStringLiteral(L10n.text(
                "error.unsupported_applescript",
                fallback: "该终端不支持 AppleScript 启动策略。"
            ))
            return "error \"\(message)\""
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
