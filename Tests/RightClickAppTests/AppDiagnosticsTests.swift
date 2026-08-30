import Foundation
import RightClickCore
import Testing

@MainActor
struct AppDiagnosticsTests {
    @Test
    func selectedTerminalIsAlwaysIncludedAndDisabledEditorsAreIgnored() {
        var configuration = MenuConfiguration(
            terminalProfileID: TerminalProfile.ghostty.rawValue
        )
        configuration.disabledActions.insert(
            RightClickAction.openInZed.configurationID
        )

        let applications = AppDiagnostics.relevantApplications(
            terminalProfile: .ghostty,
            menuConfiguration: configuration,
            applicationURL: { _ in nil }
        )

        #expect(applications.first == .ghostty)
        #expect(applications.contains(.cursor))
        #expect(!applications.contains(.zed))
        #expect(!applications.contains(.systemDefault))
    }

    @Test
    func installedEditorsAreOmittedFromTheProblemList() {
        let configuration = MenuConfiguration(
            terminalProfileID: TerminalProfile.terminal.rawValue
        )

        let applications = AppDiagnostics.relevantApplications(
            terminalProfile: .terminal,
            menuConfiguration: configuration,
            applicationURL: { application in
                application == .cursor
                    ? URL(fileURLWithPath: "/Applications/Cursor.app")
                    : nil
            }
        )

        #expect(applications.first == .terminal)
        #expect(!applications.contains(.cursor))
    }

    @Test
    func duplicateActionsProduceOnlyOneMissingApplicationDiagnostic() {
        let configuration = MenuConfiguration(
            terminalProfileID: TerminalProfile.terminal.rawValue
        )

        let applications = AppDiagnostics.relevantApplications(
            terminalProfile: .terminal,
            menuConfiguration: configuration,
            applicationURL: { _ in nil }
        )

        #expect(
            applications.filter { $0 == .visualStudioCode }.count == 1
        )
        #expect(Set(applications.map(\.identifier)).count == applications.count)
    }

    @Test
    func reportIncludesOutcomeLegendAndTerminalExecutionPolicy() {
        let items = [
            DiagnosticItem(
                id: "passing",
                title: "Passing check",
                passed: true,
                detail: "ready"
            ),
            DiagnosticItem(
                id: "failing",
                title: "Failing check",
                passed: false,
                detail: "missing"
            )
        ]

        let report = AppDiagnostics.report(
            items,
            terminalProfile: .terminal,
            terminalWindowBehavior: .newWindow
        )

        #expect(report.contains("RightClick "))
        #expect(report.contains("macOS "))
        #expect(report.contains("[OK] Passing check: ready"))
        #expect(report.contains("Failing check: missing"))
        #expect(report.contains(L10n.text(
            "diagnostic.terminal_configured_shell",
            fallback: "终端自身配置"
        )))
        #expect(report.contains(L10n.text(
            "diagnostic.authenticated_only",
            fallback: "仅接受本机 Finder 扩展认证请求"
        )))
    }

    @Test
    func appShellResolverUsesTheInjectedEnvironmentAndAccountFallback() {
        let environment = UserLoginShell.resolve(
            environment: ["SHELL": "/bin/sh"],
            passwordEntryShell: "/bin/zsh"
        )
        let accountFallback = UserLoginShell.resolve(
            environment: ["SHELL": "/definitely/missing"],
            passwordEntryShell: "/bin/zsh"
        )

        #expect(environment.path == "/bin/sh")
        #expect(accountFallback.path == "/bin/zsh")
    }
}
