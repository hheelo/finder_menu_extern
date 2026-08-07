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
        if let authenticationToken {
            components.queryItems?.append(
                URLQueryItem(name: "token", value: authenticationToken)
            )
        }
        return components.url
    }

    public init?(deepLink: URL) {
        guard let components = DeepLinkComponents(
            deepLink: deepLink,
            host: "error",
            allowedNames: ["message", "token"]
        ),
        components.queryItems.count == 2,
        let message = components.single("message"),
        !message.isEmpty,
        message.count <= Self.maximumMessageLength,
        let authenticationToken = components.single("token"),
        ExtensionRequestTokenStore.isValidToken(authenticationToken) else {
            return nil
        }

        self.message = message
        self.authenticationToken = authenticationToken
    }
}
