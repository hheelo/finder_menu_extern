import Foundation

enum AppEnvironment {
    static let uiTestingEnvironmentKey = "RIGHTCLICK_UI_TESTING"

    static var isRunningUITests: Bool {
        isRunningUITests(in: ProcessInfo.processInfo.environment)
    }

    static var isRunningTests: Bool {
        isRunningTests(in: ProcessInfo.processInfo.environment)
    }

    static func isRunningUITests(in environment: [String: String]) -> Bool {
        environment[uiTestingEnvironmentKey] == "1"
    }

    static func isRunningTests(in environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
            isRunningUITests(in: environment)
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

/// App 冷启动来源的时序状态机。
///
/// Finder URL 会早于 `applicationDidFinishLaunching` 到达。收到 URL 时必须立即
/// 收紧为无声启动，不能等到 finish 回调才分类；否则 SwiftUI `.task` 可能在两个
/// 回调之间把默认值当成用户启动，重新引入窗口或 onboarding 闪现。
struct AppLaunchState {
    private(set) var isUserLaunch = true
    private(set) var hasFinishedLaunching = false
    private var receivedDeepLinkDuringLaunch = false

    /// 返回 true 表示这是启动期 URL，调用方还需要立即隐藏默认窗口。
    mutating func receiveDeepLink() -> Bool {
        guard !hasFinishedLaunching else { return false }
        receivedDeepLinkDuringLaunch = true
        isUserLaunch = false
        return true
    }

    mutating func finish(isDefaultLaunch: Bool) {
        isUserLaunch = isDefaultLaunch && !receivedDeepLinkDuringLaunch
        hasFinishedLaunching = true
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
