import Foundation

public enum AppEnvironment {
    public static let uiTestingEnvironmentKey = "RIGHTCLICK_UI_TESTING"
    public static let closeMainWindowOnSettingsEnvironmentKey =
        "RIGHTCLICK_UI_TEST_CLOSE_MAIN_ON_SETTINGS"

    public static var isRunningUITests: Bool {
        isRunningUITests(in: ProcessInfo.processInfo.environment)
    }

    public static var isRunningTests: Bool {
        isRunningTests(in: ProcessInfo.processInfo.environment)
    }

    public static var shouldCloseMainWindowOnSettingsForUITesting: Bool {
        isRunningUITests && ProcessInfo.processInfo.environment[
            closeMainWindowOnSettingsEnvironmentKey
        ] == "1"
    }

    public static func isRunningUITests(
        in environment: [String: String]
    ) -> Bool {
        environment[uiTestingEnvironmentKey] == "1"
    }

    public static func isRunningTests(
        in environment: [String: String]
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
            isRunningUITests(in: environment)
    }
}

public enum AppPresentation {
    public static func isUserVisible(
        isUserLaunch: Bool,
        isPresentationRequested: Bool
    ) -> Bool {
        isUserLaunch || isPresentationRequested
    }
}

public struct AppLaunchState {
    public private(set) var isUserLaunch = true
    public private(set) var hasFinishedLaunching = false
    private var receivedDeepLinkDuringLaunch = false

    public init() {}

    public mutating func receiveDeepLink() -> Bool {
        guard !hasFinishedLaunching else { return false }
        receivedDeepLinkDuringLaunch = true
        isUserLaunch = false
        return true
    }

    public mutating func finish(isDefaultLaunch: Bool) {
        isUserLaunch = isDefaultLaunch && !receivedDeepLinkDuringLaunch
        hasFinishedLaunching = true
    }
}

public enum ReopenAction: Equatable {
    case restoreMainWindow
    case createMainWindow
}

public enum ReopenPolicy {
    public static func action(
        hasMainWindow: Bool,
        hasVisibleWindows _: Bool
    ) -> ReopenAction {
        hasMainWindow ? .restoreMainWindow : .createMainWindow
    }
}
