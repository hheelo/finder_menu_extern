import Foundation

/// RightClick 三个 target 共用的本地化入口。
///
/// String Catalog 跟随 RightClickCore.framework 打包，宿主和 Finder 扩展
/// 都必须显式从这个 bundle 取字符串；直接使用 `NSLocalizedString`
/// 的 main bundle 会让扩展和宿主各自找不到共享资源。
public enum L10n {
    /// 用于标记带本地化文案的持久化缓存。系统语言改变后，
    /// 旧诊断标题不应继续以上一种语言展示一天。
    public static var currentLanguageIdentifier: String {
        Bundle.preferredLocalizations(
            from: ["en", "zh-Hans"],
            forPreferences: Locale.preferredLanguages
        ).first ?? "zh-Hans"
    }

    public static func text(
        _ key: String,
        fallback: String,
        localeIdentifier: String? = nil
    ) -> String {
        localizationBundle(for: localeIdentifier).localizedString(
            forKey: key,
            value: fallback,
            table: nil
        )
    }

    public static func format(
        _ key: String,
        fallback: String,
        localeIdentifier: String? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let format = text(
            key,
            fallback: fallback,
            localeIdentifier: localeIdentifier
        )
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizationBundle(
        for localeIdentifier: String?
    ) -> Bundle {
        let frameworkBundle = Bundle(for: LocalizationBundleToken.self)
        guard let localeIdentifier else { return frameworkBundle }

        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let languageCode = normalized.split(separator: "-").first.map(String.init)
        // 系统常见的是 en-US / zh-CN，而资源目录是 en / zh-Hans。
        // 显式语言查询必须先归一到项目实际支持的语言，不能悄悄回退到
        // 当前进程语言，否则 Finder 与宿主使用不同语言时测试会出现假阳性。
        let supportedLanguage: String? = switch languageCode {
        case "en": "en"
        case "zh": "zh-Hans"
        default: nil
        }
        let candidates = [
            localeIdentifier,
            normalized,
            supportedLanguage,
            languageCode
        ].compactMap { $0 }
        for candidate in candidates {
            if let path = frameworkBundle.path(
                forResource: candidate,
                ofType: "lproj"
            ), let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return frameworkBundle
    }
}

private final class LocalizationBundleToken {}
