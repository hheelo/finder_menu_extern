import Foundation
import XCTest

@MainActor
final class RightClickUITests: XCTestCase {
    func testMainWindowCanOpenSettings() {
        continueAfterFailure = false
        let app = makeApplication()
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

    func testReopenCreatesMainWindowWhenOnlySettingsWindowRemains() throws {
        continueAfterFailure = false
        let app = makeApplication(closeMainWindowOnSettings: true)
        defer { app.terminate() }
        app.launch()

        let settingsButton = element("rightclick.main.settings", in: app)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.click()
        XCTAssertTrue(
            element("rightclick.settings.menu.collapse", in: app)
                .waitForExistence(timeout: 10)
        )

        XCTAssertTrue(
            element("rightclick.main.settings", in: app)
                .waitForNonExistence(timeout: 5)
        )

        try reopenTestHostThroughLaunchServices()

        XCTAssertTrue(
            element("rightclick.main.settings", in: app)
                .waitForExistence(timeout: 10),
            "Reopening with a settings window must recreate the main window"
        )
    }

    private func makeApplication(
        closeMainWindowOnSettings: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RIGHTCLICK_UI_TESTING"] = "1"
        if closeMainWindowOnSettings {
            app.launchEnvironment[
                "RIGHTCLICK_UI_TEST_CLOSE_MAIN_ON_SETTINGS"
            ] = "1"
        }
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        return app
    }

    private func reopenTestHostThroughLaunchServices() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", "com.hheelo.RightClick.UITestHost"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func element(
        _ identifier: String,
        in root: XCUIElement
    ) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
