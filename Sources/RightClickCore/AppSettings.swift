import Foundation

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private enum Key {
        static let terminalProfile = "terminalProfile"
        static let confirmCLIExecution = "confirmCLIExecution"
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

    public var confirmCLIExecution: Bool {
        get {
            defaults.object(forKey: Key.confirmCLIExecution) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: Key.confirmCLIExecution)
        }
    }
}
