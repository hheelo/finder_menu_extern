import Foundation

public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private enum Key {
        static let terminalProfile = "terminalProfile"
        static let finderSessionBuild = "finderSessionBuild"
        static let cachedDiagnostics = "cachedDiagnostics"
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

    public var finderSessionBuild: String? {
        get { defaults.string(forKey: Key.finderSessionBuild) }
        set { defaults.set(newValue, forKey: Key.finderSessionBuild) }
    }

    public var cachedDiagnostics: Data? {
        get { defaults.data(forKey: Key.cachedDiagnostics) }
        set { defaults.set(newValue, forKey: Key.cachedDiagnostics) }
    }
}
