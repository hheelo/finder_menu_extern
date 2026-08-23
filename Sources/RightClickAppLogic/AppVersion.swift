import Foundation
import RightClickCore

public struct AppVersion: Equatable {
    public let shortVersion: String
    public let build: String?

    public init(shortVersion: String, build: String?) {
        self.shortVersion = shortVersion
        self.build = build
    }

    public var displayString: String {
        guard let build else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }

    public var accessibilityLabel: String {
        guard let build else { return shortVersion }
        return L10n.format(
            "home.version",
            fallback: "版本 %1$@，构建 %2$@",
            shortVersion,
            build
        )
    }

    public static var current: AppVersion? {
        resolve(infoDictionary: Bundle.main.infoDictionary)
    }

    public static var displayString: String? { current?.displayString }

    public static func resolve(
        infoDictionary: [String: Any]?
    ) -> AppVersion? {
        guard let short = infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String, !short.isEmpty else {
            return nil
        }
        let build = infoDictionary?["CFBundleVersion"] as? String
        return AppVersion(
            shortVersion: short,
            build: build?.isEmpty == false ? build : nil
        )
    }
}
