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
    public let authenticationToken: String?

    public init(
        workingDirectory: URL,
        authenticationToken: String? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.authenticationToken = authenticationToken
    }

    public var deepLink: URL? {
        deepLink(now: Date(), nonce: UUID().uuidString)
    }

    public func deepLink(now: Date, nonce: String) -> URL? {
        guard workingDirectory.isFileURL,
              workingDirectory.path.hasPrefix("/"),
              authenticationToken.map(
                  ExtensionRequestTokenStore.isValidToken
              ) ?? true else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "terminal"
        components.queryItems = [
            URLQueryItem(name: "cwd", value: workingDirectory.path)
        ]
        return DeepLinkSignature.signedURL(
            components: components,
            token: authenticationToken,
            now: now,
            nonce: nonce
        )
    }

    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard let components = DeepLinkComponents(
            deepLink: deepLink,
            host: "terminal",
            allowedNames: [
                "cwd", "v", "ts", "nonce", "sig"
            ]
        ),
              DeepLinkSignature.authentication(in: deepLink) != nil,
              let path = components.single("cwd"),
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
        self.authenticationToken = nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workingDirectory == rhs.workingDirectory
    }
}
