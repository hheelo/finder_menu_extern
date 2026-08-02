import Foundation
import Testing
@testable import RightClickCore

struct AppSettingsTests {
    @Test
    func cliConfirmationDefaultsToDisabledAndPersists() throws {
        let suiteName = "RightClickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.confirmCLIExecution == false)

        settings.confirmCLIExecution = true
        #expect(settings.confirmCLIExecution == true)
    }

    @Test
    func terminalProfileDefaultsToAutomatic() throws {
        let suiteName = "RightClickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.terminalProfile == .automatic)

        settings.terminalProfile = .terminal
        #expect(settings.terminalProfile == .terminal)
    }

    @Test
    func finderSessionBuildPersists() throws {
        let suiteName = "RightClickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.finderSessionBuild == nil)

        settings.finderSessionBuild = "5"
        #expect(settings.finderSessionBuild == "5")
    }

    @Test
    func parsesLegacyPlugInKitElectionMarkers() {
        let enabled = """
              +    com.hheelo.RightClick.FinderExtension(502) /Applications/RightClick.app
              -    com.example.Disabled(1) /Applications/Disabled.app
            """
        let debuggerEnabled = """
              !    com.hheelo.RightClick.FinderExtension(502) /tmp/RightClick.app
            """
        let disabled = """
              -    com.hheelo.RightClick.FinderExtension(502) /Applications/RightClick.app
              =    com.hheelo.RightClick.FinderExtension(501) /tmp/RightClick.app
            """

        #expect(AppConstants.plugInKitOutputIndicatesEnabled(enabled))
        #expect(AppConstants.plugInKitOutputIndicatesEnabled(debuggerEnabled))
        #expect(!AppConstants.plugInKitOutputIndicatesEnabled(disabled))
        #expect(!AppConstants.plugInKitOutputIndicatesEnabled(""))
    }
}
