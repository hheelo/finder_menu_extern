import Foundation

enum AppEnvironment {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum AppPresentation {
    /// 界面是否真的呈现给用户：既包括进程由用户启动，也包括深链无声启动后
    /// 用户再次双击、显式把窗口请出来。
    static func isUserVisible(
        isUserLaunch: Bool,
        isPresentationRequested: Bool
    ) -> Bool {
        isUserLaunch || isPresentationRequested
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
