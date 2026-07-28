import Foundation

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private enum Key {
        static let terminalProfile = "terminalProfile"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var terminalProfile: TerminalProfile {
        get {
            defaults.string(forKey: Key.terminalProfile)
                .flatMap(TerminalProfile.init(rawValue:)) ?? .terminal
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.terminalProfile)
        }
    }
}
