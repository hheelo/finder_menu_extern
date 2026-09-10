import Foundation
@testable import RightClickAppLogic
import RightClickCore
import Testing

struct TerminalLaunchPlanTests {
    private let directory = URL(fileURLWithPath: "/tmp/project with space")
    private let shell = URL(fileURLWithPath: "/bin/zsh")

    @Test
    func openingDirectoryPlansEveryTerminalAndWindowBehavior() throws {
        let terminal = try #require(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .terminal,
            terminalWindowBehavior: .newTab
        ))
        #expect(terminal == .openFiles(
            application: .terminal,
            urls: [directory]
        ))

        let automatic = try #require(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .automatic,
            terminalWindowBehavior: .newWindow
        ))
        #expect(automatic == .openFiles(
            application: .terminal,
            urls: [directory]
        ))

        let warpTab = try #require(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .warp,
            terminalWindowBehavior: .newTab
        ))
        guard case let .openURL(warpURL) = warpTab else {
            Issue.record("Warp should use its URL scheme")
            return
        }
        #expect(warpURL.host == "action")
        #expect(warpURL.path == "/new_tab")
        #expect(URLComponents(url: warpURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first?.value == directory.path)

        #expect(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .ghostty,
            terminalWindowBehavior: .newWindow
        ) == .launchApplication(
            application: .ghostty,
            arguments: ["--working-directory=\(directory.path)"],
            createsNewInstance: true
        ))
        #expect(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .wezTerm,
            terminalWindowBehavior: .newTab
        ) == .launchApplication(
            application: .wezTerm,
            arguments: ["start", "--cwd", directory.path, "--new-tab"],
            createsNewInstance: false
        ))
        #expect(TerminalLaunchPlan.openingDirectory(
            directory,
            terminalProfile: .kitty,
            terminalWindowBehavior: .newTab
        ) == .launchApplication(
            application: .kitty,
            arguments: ["--directory", directory.path],
            createsNewInstance: true
        ))
    }

    @Test
    func executableCommandPlansPreserveShellAndWindowSemantics() throws {
        let command = "cd '/tmp/project with space' && codex"
        let wezTerm = try #require(TerminalLaunchPlan.runningCommand(
            command,
            in: directory,
            terminalProfile: .wezTerm,
            terminalWindowBehavior: .newTab,
            loginShellURL: shell
        ))
        #expect(wezTerm == .launchApplication(
            application: .wezTerm,
            arguments: [
                "start", "--cwd", directory.path, "--new-tab", "--",
                shell.path, "-lic", command
            ],
            createsNewInstance: false
        ))

        let kitty = try #require(TerminalLaunchPlan.runningCommand(
            command,
            in: directory,
            terminalProfile: .kitty,
            terminalWindowBehavior: .newWindow,
            loginShellURL: URL(fileURLWithPath: "/opt/homebrew/bin/fish")
        ))
        #expect(kitty == .launchApplication(
            application: .kitty,
            arguments: [
                "--directory", directory.path, "--", "/opt/homebrew/bin/fish",
                "-l", "-i", "-c", command
            ],
            createsNewInstance: true
        ))
    }

    @Test
    func appleScriptPlansCarryCommandAsAnArgument() throws {
        let command = "cd '/tmp' && printf '%s' 'safe'"
        let terminal = try #require(TerminalLaunchPlan.runningCommand(
            command,
            in: directory,
            terminalProfile: .terminal,
            terminalWindowBehavior: .newTab,
            loginShellURL: shell
        ))
        guard case let .runAppleScript(script, argument) = terminal else {
            Issue.record("Terminal should use AppleScript")
            return
        }
        #expect(script.contains("System Events"))
        #expect(script.contains("repeat 20 times"))
        #expect(argument == command)

        #expect(TerminalLaunchPlan.runningCommand(
            command,
            in: directory,
            terminalProfile: .warp,
            terminalWindowBehavior: .newTab,
            loginShellURL: shell
        ) == nil)
        #expect(TerminalLaunchPlan.runningCommand(
            command,
            in: directory,
            terminalProfile: .ghostty,
            terminalWindowBehavior: .newWindow,
            loginShellURL: shell
        ) == nil)
    }
}
