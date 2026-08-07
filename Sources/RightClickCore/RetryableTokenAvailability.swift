import Foundation

/// 缓存成功取得的令牌，但不缓存失败：下一次动作必须能够重新尝试。
public struct RetryableTokenAvailability: Sendable {
    private var cachedToken: String?

    public init() {}

    public mutating func current(
        load: () throws -> String
    ) -> String? {
        if let cachedToken { return cachedToken }
        guard let token = try? load(),
              ExtensionRequestTokenStore.isValidToken(token) else {
            return nil
        }
        cachedToken = token
        return token
    }
}
