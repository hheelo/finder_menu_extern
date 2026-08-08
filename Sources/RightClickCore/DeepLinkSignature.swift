import CryptoKit
import Foundation

public struct SignedDeepLinkAuthentication: Equatable, Sendable {
    public let timestamp: Int64
    public let nonce: String
    public let signature: String
}

public enum DeepLinkAuthentication: Equatable, Sendable {
    case unsigned
    case legacyToken(String)
    case signed(SignedDeepLinkAuthentication)
}

/// 用扩展容器中的随机密钥签名深链，密钥本身不再进入 URL。
///
/// 时间窗口限制签名的可用期，nonce 的单次使用由宿主进程内的
/// `NonceCache` 保证。宿主退出后缓存会清空，因此进程重启后的窗口内
/// 重放仍是已知限制；为此落盘 nonce 的成本高于 30 秒窗口的收益。
public enum DeepLinkSignature {
    public static let version = 2
    public static let validityWindow: TimeInterval = 30

    private static let authenticationNames: Set<String> = [
        "v", "ts", "nonce", "sig", "token"
    ]

    public static func signedURL(
        components: URLComponents,
        token: String?,
        now: Date = Date(),
        nonce: String = UUID().uuidString
    ) -> URL? {
        guard let token else { return components.url }
        guard let key = signingKey(token: token),
              UUID(uuidString: nonce) != nil,
              let host = components.host,
              let semanticItems = components.queryItems,
              semanticItems.allSatisfy({
                  !authenticationNames.contains($0.name) && $0.value != nil
              }) else {
            return nil
        }

        let timestamp = Int64(now.timeIntervalSince1970.rounded(.towardZero))
        guard timestamp > 0 else { return nil }
        let payload = payloadData(
            host: host,
            parameters: semanticItems,
            timestamp: timestamp,
            nonce: nonce
        )
        let code = HMAC<SHA256>.authenticationCode(
            for: payload,
            using: key
        )

        var signed = components
        signed.queryItems = semanticItems + [
            URLQueryItem(name: "v", value: String(version)),
            URLQueryItem(name: "ts", value: String(timestamp)),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "sig", value: Data(code).base64EncodedString())
        ]
        return signed.url
    }

    public static func authentication(
        in deepLink: URL
    ) -> DeepLinkAuthentication? {
        guard let components = URLComponents(
            url: deepLink,
            resolvingAgainstBaseURL: false
        ), let queryItems = components.queryItems else {
            return nil
        }
        let authenticationItems = queryItems.filter {
            authenticationNames.contains($0.name)
        }
        if authenticationItems.isEmpty {
            return .unsigned
        }

        if authenticationItems.count == 1,
           let token = single("token", in: authenticationItems),
           ExtensionRequestTokenStore.isValidToken(token) {
            return .legacyToken(token)
        }

        guard authenticationItems.count == 4,
              single("v", in: authenticationItems) == String(version),
              let timestampText = single("ts", in: authenticationItems),
              let timestamp = Int64(timestampText),
              String(timestamp) == timestampText,
              timestamp > 0,
              let nonce = single("nonce", in: authenticationItems),
              UUID(uuidString: nonce) != nil,
              let signature = single("sig", in: authenticationItems),
              let signatureData = Data(base64Encoded: signature),
              signatureData.count == SHA256.Digest.byteCount,
              signatureData.base64EncodedString() == signature else {
            return nil
        }
        return .signed(
            SignedDeepLinkAuthentication(
                timestamp: timestamp,
                nonce: nonce,
                signature: signature
            )
        )
    }

    public static func verify(
        _ authentication: SignedDeepLinkAuthentication,
        deepLink: URL,
        token: String,
        now: Date = Date()
    ) -> Bool {
        let age = now.timeIntervalSince1970 - Double(authentication.timestamp)
        guard abs(age) <= validityWindow,
              let key = signingKey(token: token),
              let signature = Data(base64Encoded: authentication.signature),
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ), let host = components.host,
              let queryItems = components.queryItems else {
            return false
        }
        let semanticItems = queryItems.filter {
            !authenticationNames.contains($0.name)
        }
        let payload = payloadData(
            host: host,
            parameters: semanticItems,
            timestamp: authentication.timestamp,
            nonce: authentication.nonce
        )
        return HMAC<SHA256>.isValidAuthenticationCode(
            signature,
            authenticating: payload,
            using: key
        )
    }

    private static func signingKey(token: String) -> SymmetricKey? {
        guard ExtensionRequestTokenStore.isValidToken(token),
              let data = Data(base64Encoded: token) else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    /// 长度前缀避免路径中的换行、等号等字符造成字段边界歧义。
    /// 参数顺序是协议的一部分；修改顺序必须导致验签失败。
    private static func payloadData(
        host: String,
        parameters: [URLQueryItem],
        timestamp: Int64,
        nonce: String
    ) -> Data {
        let fields = ["v(version)", host]
            + parameters.flatMap { [$0.name, $0.value ?? ""] }
            + [String(timestamp), nonce]
        let canonical = fields.map { value in
            "\(value.utf8.count):\(value)"
        }.joined()
        return Data(canonical.utf8)
    }

    private static func single(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        let matching = items.filter { $0.name == name }
        guard matching.count == 1 else { return nil }
        return matching[0].value
    }
}
