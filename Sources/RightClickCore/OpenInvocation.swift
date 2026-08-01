import Foundation

/// 请求宿主 App 用某个外部 App 打开若干路径。
///
/// 沙箱化的 Finder 扩展不能启动其他应用（LaunchServices 会直接返回错误），
/// 因此「用 VS Code 打开」这类动作只能由未沙箱的宿主执行。扩展把请求编码成
/// `rightclick://open` 深链，用 `NSWorkspace.open(_ url:)` 唤起宿主——
/// 打开 URL 是沙箱允许的，指定 App 去启动则不是。
public struct OpenInvocation: Equatable, Sendable {
    public let application: ExternalApplication
    public let targets: [URL]

    public init(application: ExternalApplication, targets: [URL]) {
        self.application = application
        self.targets = targets
    }

    public var deepLink: URL? {
        guard !targets.isEmpty,
              targets.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "open"
        components.queryItems =
            [URLQueryItem(name: "app", value: application.identifier)]
            + targets.map { URLQueryItem(name: "path", value: $0.path) }
        return components.url
    }

    /// 严格解析：只接受白名单内的 App 标识，路径必须是已存在的绝对路径。
    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard deepLink.scheme == AppConstants.deepLinkScheme,
              deepLink.host == "open",
              deepLink.user == nil,
              deepLink.password == nil,
              deepLink.port == nil,
              deepLink.fragment == nil,
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ),
              let queryItems = components.queryItems,
              queryItems.allSatisfy({ $0.name == "app" || $0.name == "path" }),
              queryItems.filter({ $0.name == "app" }).count == 1,
              let identifier = queryItems
                  .first(where: { $0.name == "app" })?.value,
              let application = ExternalApplication(identifier: identifier)
        else {
            return nil
        }

        let paths = queryItems
            .filter { $0.name == "path" }
            .compactMap(\.value)
        guard !paths.isEmpty,
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
    }
}
