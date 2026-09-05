import AppKit
import Foundation
import XCTest

@MainActor
final class RightClickUITests: XCTestCase {
    func testHomeWithFinderExtensionEnabled() {
        assertHome(extensionEnabled: true)
    }

    func testHomeWithFinderExtensionDisabled() {
        assertHome(extensionEnabled: false)
    }

    private func assertHome(extensionEnabled: Bool) {
        continueAfterFailure = false
        let app = makeApplication(extensionEnabled: extensionEnabled)
        defer { app.terminate() }
        app.launch()
        app.activate()

        let status = element("rightclick.main.extension-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        // macOS StaticText 的显示文本通过 value 暴露，label 通常为空。
        XCTAssertEqual(status.value as? String, extensionEnabled
            ? "Finder extension enabled" : "Finder extension off")
        let extensionButton = app.buttons["rightclick.main.extension-settings"]
        XCTAssertEqual(extensionButton.label, extensionEnabled
            ? "Manage Extension" : "Enable Finder Extension")
        XCTAssertTrue(extensionButton.isEnabled)
        XCTAssertTrue(extensionButton.isHittable)

        // 检查入口可点击；不依赖线上 appcast，也不启动真实更新流程。
        let updates = app.buttons["rightclick.main.check-updates"]
        XCTAssertTrue(updates.exists)
        XCTAssertTrue(updates.isEnabled)
        XCTAssertTrue(updates.isHittable)

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []
        defer {
            pasteboard.clearContents()
            let restored = savedItems.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(restored)
        }
        pasteboard.clearContents()
        pasteboard.setString("UI regression sentinel", forType: .string)
        let copy = app.buttons["rightclick.main.copy-diagnostics"]
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(copy.isHittable)
        copy.click()
        let copied = element("rightclick.main.last-status", in: app)
        expectation(
            for: NSPredicate(format: "value == %@", "Diagnostics copied"),
            evaluatedWith: copied
        )
        waitForExpectations(timeout: 5)
        let report = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(report.hasPrefix("RightClick "))
        XCTAssertTrue(report.contains("macOS "))

        let settings = app.buttons["rightclick.main.settings"]
        XCTAssertTrue(settings.isHittable)
        settings.click()
        XCTAssertTrue(element("rightclick.settings.menu.collapse", in: app)
            .waitForExistence(timeout: 10))
    }

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
        extensionEnabled: Bool = false,
        closeMainWindowOnSettings: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RIGHTCLICK_UI_TESTING"] = "1"
        app.launchEnvironment["RIGHTCLICK_UI_TEST_EXTENSION_ENABLED"] =
            extensionEnabled ? "1" : "0"
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
        // 同一个 Bundle ID 可能同时存在于多个 DerivedData。`open -b` 会交给
        // LaunchServices 自行挑一份，容易重开旧构建而让当前 XCUIApplication
        // 永远等不到窗口。测试 bundle 与宿主都在同一个 Products 目录，显式
        // 使用这次构建的路径才能保证重开的是当前受控进程。
        let productsDirectory = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testHost = productsDirectory.appendingPathComponent(
            "RightClickUITestHost.app",
            isDirectory: true
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: testHost.path),
            "The current UI test host must exist at \(testHost.path)"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [testHost.path]
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
