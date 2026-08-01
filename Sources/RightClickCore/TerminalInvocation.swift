import Foundation

/// 请求宿主在某个目录打开终端。
///
/// 为什么不由扩展直接决定用哪个终端：扩展是沙箱化的，有独立的 UserDefaults，
/// 而 App Group 已被移除，所以它读不到用户在设置里选的「默认终端」。把选择权
/// 留给宿主，菜单动作和「运行 AI CLI」才会遵循同一套优先级与回退规则。
///
/// 与 `OpenInvocation` 分开是有意的：那个深链携带确定的 App 标识，而这里携带的
/// 是「用户的终端」这一意图，具体是哪个 App 由宿主在收到时才解析。
public struct TerminalInvocation: Equatable, Sendable {
    public let workingDirectory: URL

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    public var deepLink: URL? {
        guard workingDirectory.isFileURL,
              workingDirectory.path.hasPrefix("/") else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "terminal"
        components.queryItems = [
            URLQueryItem(name: "cwd", value: workingDirectory.path)
        ]
        return components.url
    }

    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard deepLink.scheme == AppConstants.deepLinkScheme,
              deepLink.host == "terminal",
              deepLink.user == nil,
              deepLink.password == nil,
              deepLink.port == nil,
              deepLink.fragment == nil,
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ),
              let queryItems = components.queryItems,
              queryItems.count == 1,
              let item = queryItems.first,
              item.name == "cwd",
              let path = item.value,
              path.hasPrefix("/") else {
            return nil
        }

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

        self.workingDirectory = directory
    }
}
