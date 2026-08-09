import Foundation

/// 请求宿主 App 用某个外部 App 打开若干路径。
///
/// 沙箱化的 Finder 扩展不能启动其他应用（LaunchServices 会直接返回错误），
/// 因此「用 VS Code 打开」这类动作只能由未沙箱的宿主执行。扩展把请求编码成
/// `rightclick://open` 深链，用 `NSWorkspace.open(_ url:)` 唤起宿主——
/// 打开 URL 是沙箱允许的，指定 App 去启动则不是。
public struct OpenInvocation: Equatable, Sendable {
    /// 显式限制而不是静默截断：少打开几个文件会让用户误以为全部成功。
    /// LaunchServices 的 URL 长度上限属于实现细节，这里只负责给请求设一个
    /// 可预期的边界，不把 128 当作系统阈值。
    public static let maximumTargets = 128

    public let application: ExternalApplication
    public let targets: [URL]
    public let authenticationToken: String?

    public init(
        application: ExternalApplication,
        targets: [URL],
        authenticationToken: String? = nil
    ) {
        self.application = application
        self.targets = targets
        self.authenticationToken = authenticationToken
    }

    public var deepLink: URL? {
        deepLink(now: Date(), nonce: UUID().uuidString)
    }

    public func deepLink(now: Date, nonce: String) -> URL? {
        guard !targets.isEmpty,
              targets.count <= Self.maximumTargets,
              targets.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }),
              authenticationToken.map(
                  ExtensionRequestTokenStore.isValidToken
              ) ?? true else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "open"
        components.queryItems =
            [URLQueryItem(name: "app", value: application.identifier)]
            + targets.map { URLQueryItem(name: "path", value: $0.path) }
        return DeepLinkSignature.signedURL(
            components: components,
            token: authenticationToken,
            now: now,
            nonce: nonce
        )
    }

    /// 严格解析：只接受白名单内的 App 标识，路径必须是已存在的绝对路径。
    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard let components = DeepLinkComponents(
            deepLink: deepLink,
            host: "open",
            allowedNames: [
                "app", "path", "v", "ts", "nonce", "sig"
            ]
        ),
              DeepLinkSignature.authentication(in: deepLink) != nil,
              let identifier = components.single("app"),
              let application = ExternalApplication(identifier: identifier)
        else {
            return nil
        }

        let paths = components.all("path")
        guard !paths.isEmpty,
              paths.count <= Self.maximumTargets,
              paths.allSatisfy({ $0.hasPrefix("/") }) else {
            return nil
        }

        let urls = paths.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        guard urls.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return nil
        }

        self.application = application
        self.targets = urls
        self.authenticationToken = nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.application == rhs.application && lhs.targets == rhs.targets
    }
}
