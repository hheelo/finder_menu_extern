import Foundation
import RightClickCore

/// App 版本的唯一读取点。界面、诊断报告和 Finder 会话刷新共用同一份拼装，
/// 避免短版本号与构建号在不同路径上漂移。
struct AppVersion: Equatable {
    let shortVersion: String
    let build: String?

    var displayString: String {
        guard let build else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }

    var accessibilityLabel: String {
        guard let build else { return shortVersion }
        return L10n.format(
            "home.version",
            fallback: "版本 %1$@，构建 %2$@",
            shortVersion,
            build
        )
    }

    static var current: AppVersion? {
        resolve(infoDictionary: Bundle.main.infoDictionary)
    }

    static var displayString: String? { current?.displayString }

    static func resolve(infoDictionary: [String: Any]?) -> AppVersion? {
        guard let short = infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else {
            return nil
        }
        let build = infoDictionary?["CFBundleVersion"] as? String
        return AppVersion(
            shortVersion: short,
            build: build?.isEmpty == false ? build : nil
        )
    }
}
