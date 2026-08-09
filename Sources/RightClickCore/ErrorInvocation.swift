import Foundation

/// Finder 扩展无法安全展示模态错误，因此把可信错误交给宿主通知用户。
/// 消息只作为纯文本展示；长度限制防止被异常输入刷屏。
public struct ErrorInvocation: Equatable, Sendable {
    public static let maximumMessageLength = 300

    public let message: String
    public let authenticationToken: String?

    public init(
        message: String,
        authenticationToken: String? = nil
    ) {
        self.message = message
        self.authenticationToken = authenticationToken
    }

    public var deepLink: URL? {
        deepLink(now: Date(), nonce: UUID().uuidString)
    }

    public func deepLink(now: Date, nonce: String) -> URL? {
        guard !message.isEmpty,
              message.count <= Self.maximumMessageLength,
              authenticationToken.map(
                  ExtensionRequestTokenStore.isValidToken
              ) ?? true else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "error"
        components.queryItems = [URLQueryItem(name: "message", value: message)]
        return DeepLinkSignature.signedURL(
            components: components,
            token: authenticationToken,
            now: now,
            nonce: nonce
        )
    }

    public init?(deepLink: URL) {
        guard let components = DeepLinkComponents(
            deepLink: deepLink,
            host: "error",
            allowedNames: [
                "message", "v", "ts", "nonce", "sig"
            ]
        ),
        DeepLinkSignature.authentication(in: deepLink) != nil,
        let message = components.single("message"),
        !message.isEmpty,
        message.count <= Self.maximumMessageLength else {
            return nil
        }

        self.message = message
        self.authenticationToken = nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message
    }
}
