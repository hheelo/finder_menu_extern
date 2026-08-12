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
}
