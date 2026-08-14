import Foundation

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private enum Key {
        static let terminalProfile = "terminalProfile"
        static let terminalWindowBehavior = "terminalWindowBehavior"
        static let finderSessionBuild = "finderSessionBuild"
        static let cachedDiagnostics = "cachedDiagnostics"
        static let menuBarIconEnabled = "menuBarIconEnabled"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var terminalProfile: TerminalProfile {
        get {
            defaults.string(forKey: Key.terminalProfile)
                .flatMap(TerminalProfile.init(rawValue:)) ?? .automatic
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.terminalProfile)
        }
    }

    public var terminalWindowBehavior: TerminalWindowBehavior {
        get {
            defaults.string(forKey: Key.terminalWindowBehavior)
                .flatMap(TerminalWindowBehavior.init(rawValue:)) ?? .newTab
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.terminalWindowBehavior)
        }
    }

    public var finderSessionBuild: String? {
        get { defaults.string(forKey: Key.finderSessionBuild) }
        set { defaults.set(newValue, forKey: Key.finderSessionBuild) }
    }

    public var cachedDiagnostics: Data? {
        get { defaults.data(forKey: Key.cachedDiagnostics) }
        set { defaults.set(newValue, forKey: Key.cachedDiagnostics) }
    }

    public var menuBarIconEnabled: Bool {
        get { defaults.bool(forKey: Key.menuBarIconEnabled) }
        set { defaults.set(newValue, forKey: Key.menuBarIconEnabled) }
    }

    public var hasCompletedOnboarding: Bool {
        get {
            if defaults.object(forKey: Key.hasCompletedOnboarding) != nil {
                return defaults.bool(forKey: Key.hasCompletedOnboarding)
            }
            // v1.0.0 前没有 onboarding 标记。已有任一持久状态说明这是升级用户，
            // 不应在更新后突然弹出“首次启动”向导；完全空白的 defaults 才是新用户。
            return defaults.object(forKey: Key.terminalProfile) != nil
                || defaults.object(forKey: Key.terminalWindowBehavior) != nil
                || defaults.object(forKey: Key.finderSessionBuild) != nil
                || defaults.object(forKey: Key.cachedDiagnostics) != nil
                || defaults.object(forKey: Key.menuBarIconEnabled) != nil
        }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
