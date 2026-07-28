import Foundation

public final class SharedSettings: @unchecked Sendable {
    public static let shared = SharedSettings()

    private enum Key {
        static let terminalProfile = "terminalProfile"
        static let monitoredPaths = "monitoredPaths"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: AppConstants.appGroupIdentifier)
            ?? .standard
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

    public var monitoredURLs: Set<URL> {
        get {
            let paths = defaults.stringArray(forKey: Key.monitoredPaths) ?? ["/"]
            return Set(paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        }
        set {
            defaults.set(newValue.map(\.path).sorted(), forKey: Key.monitoredPaths)
        }
    }
}
