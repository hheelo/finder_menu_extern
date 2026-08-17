import Foundation

/// 由 Finder 扩展生成、通过本机密钥签名后交给宿主的深链请求。
///
/// 查询项顺序是已发布的签名协议的一部分。各请求只提供按既有顺序排列的业务
/// 查询项，scheme、host、认证字段与签名收尾由这里统一处理。
public protocol SignedInvocation: Sendable {
    static var deepLinkHost: String { get }
    var authenticationToken: String? { get }
    var deepLinkQueryItems: [URLQueryItem]? { get }
}

public extension SignedInvocation {
    var deepLink: URL? {
        deepLink(now: Date(), nonce: UUID().uuidString)
    }

    func deepLink(now: Date, nonce: String) -> URL? {
        guard authenticationToken.map(
            ExtensionRequestTokenStore.isValidToken
        ) ?? true,
        let queryItems = deepLinkQueryItems else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = Self.deepLinkHost
        components.queryItems = queryItems
        return DeepLinkSignature.signedURL(
            components: components,
            token: authenticationToken,
            now: now,
            nonce: nonce
        )
    }
}
