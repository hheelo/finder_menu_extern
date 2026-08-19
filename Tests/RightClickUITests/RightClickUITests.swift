import XCTest

@MainActor
final class RightClickUITests: XCTestCase {
    func testMainWindowCanOpenSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["RIGHTCLICK_UI_TESTING"] = "1"
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        defer { app.terminate() }
        app.launch()

        let extensionSettings = element(
            "rightclick.main.extension-settings",
            in: app
        )
        XCTAssertTrue(
            extensionSettings.waitForExistence(timeout: 10),
            "The signed host should render its main window"
        )

        let settingsButton = element("rightclick.main.settings", in: app)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        XCTAssertTrue(
            element("rightclick.settings.menu.collapse", in: app)
                .waitForExistence(timeout: 10),
            "Settings should open on the menu tab"
        )
    }

    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
