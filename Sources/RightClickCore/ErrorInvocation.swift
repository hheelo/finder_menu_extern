import Foundation

/// Finder 扩展无法安全展示模态错误，因此把可信错误交给宿主通知用户。
/// 消息只作为纯文本展示；长度限制防止被异常输入刷屏。
public struct ErrorInvocation: Equatable, SignedInvocation, Sendable {
    public static let deepLinkHost = "error"

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

    public var deepLinkQueryItems: [URLQueryItem]? {
        guard !message.isEmpty,
              message.count <= Self.maximumMessageLength else {
            return nil
        }
        return [URLQueryItem(name: "message", value: message)]
    }

    public init?(deepLink: URL) {
        guard let components = DeepLinkComponents.authenticated(
            deepLink: deepLink,
            host: Self.deepLinkHost,
            semanticNames: ["message"]
        ),
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
