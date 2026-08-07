import Foundation

/// RightClick 深链共用的严格结构校验。
///
/// 每种 invocation 只负责自己的字段语义；协议、host、凭据、fragment 和查询项
/// 白名单在这里统一检查，避免不同动作的安全边界随复制粘贴逐渐漂移。
struct DeepLinkComponents {
    let queryItems: [URLQueryItem]

    init?(
        deepLink: URL,
        host: String,
        allowedNames: Set<String>
    ) {
        guard deepLink.scheme == AppConstants.deepLinkScheme,
              deepLink.host == host,
              deepLink.user == nil,
              deepLink.password == nil,
              deepLink.port == nil,
              deepLink.fragment == nil,
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ),
              let queryItems = components.queryItems,
              queryItems.allSatisfy({
                  allowedNames.contains($0.name) && $0.value != nil
              }) else {
            return nil
        }
        self.queryItems = queryItems
    }

    func single(_ name: String) -> String? {
        let matching = queryItems.filter { $0.name == name }
        guard matching.count == 1 else { return nil }
        return matching[0].value
    }

    func optionalSingle(_ name: String) -> String? {
        let matching = queryItems.filter { $0.name == name }
        guard matching.count <= 1 else { return nil }
        return matching.first?.value
    }

    func count(of name: String) -> Int {
        queryItems.count { $0.name == name }
    }

    func all(_ name: String) -> [String] {
        queryItems.filter { $0.name == name }.compactMap(\.value)
    }
}
