import Foundation
import Testing
@testable import RightClickCore

struct AppSettingsTests {
    @Test
    func terminalProfileDefaultsToAutomatic() throws {
        let suiteName = "RightClickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        #expect(settings.terminalProfile == .automatic)
        #expect(settings.terminalWindowBehavior == .newTab)
        #expect(!settings.menuBarIconEnabled)

        settings.terminalProfile = .terminal
        #expect(settings.terminalProfile == .terminal)
        settings.terminalWindowBehavior = .newWindow
        #expect(settings.terminalWindowBehavior == .newWindow)
        settings.menuBarIconEnabled = true
        #expect(settings.menuBarIconEnabled)
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
    func diagnosticsCachePersists() throws {
        let suiteName = "RightClickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let data = Data("cached".utf8)

        #expect(settings.cachedDiagnostics == nil)
        settings.cachedDiagnostics = data
        #expect(settings.cachedDiagnostics == data)
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
