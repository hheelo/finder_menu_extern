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
        Self.single(name, in: queryItems)
    }

    static func single(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        let matching = items.filter { $0.name == name }
        guard matching.count == 1 else { return nil }
        return matching[0].value
    }

    func all(_ name: String) -> [String] {
        queryItems.filter { $0.name == name }.compactMap(\.value)
    }

    /// 三种终端类请求共用同一条路径边界：字段只能出现一次，必须是现有的
    /// 绝对目录，并在进入业务层前统一标准化。
    func existingAbsoluteDirectory(
        _ name: String,
        fileManager: FileManager
    ) -> URL? {
        guard let path = single(name), path.hasPrefix("/") else { return nil }

        let directory = URL(
            fileURLWithPath: path,
            isDirectory: true
        ).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return nil
        }
        return directory
    }
}
