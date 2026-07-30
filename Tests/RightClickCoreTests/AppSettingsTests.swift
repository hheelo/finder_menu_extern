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
    func iTermActionHasAnExplicitMenuTitle() {
        #expect(
            RightClickAction.openInTerminal(.iTerm).title
                == "在 iTerm2 中打开"
        )
    }
}
