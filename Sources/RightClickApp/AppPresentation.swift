import Foundation

enum AppEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum ReopenAction: Equatable {
    case keepVisible
    case restoreExisting
    case createWindow
}

enum ReopenPolicy {
    static func action(
        hasVisibleWindows: Bool,
        hasPresentableWindow: Bool
    ) -> ReopenAction {
        if hasPresentableWindow { return .restoreExisting }
        if hasVisibleWindows { return .keepVisible }
        return .createWindow
    }
}
