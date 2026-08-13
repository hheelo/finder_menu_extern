import Foundation

public struct CLIInvocation: Equatable, Sendable {
    public let command: CLICommand
    public let workingDirectory: URL
    public let authenticationToken: String?

    public init(
        command: CLICommand,
        workingDirectory: URL,
        authenticationToken: String? = nil
    ) {
        self.command = command
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
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: command.rawValue),
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
            host: "run",
            allowedNames: [
                "tool", "cwd", "v", "ts", "nonce", "sig"
            ]
        ),
              DeepLinkSignature.authentication(in: deepLink) != nil,
              let tool = components.single("tool"),
              let command = CLICommand(rawValue: tool),
              let directory = components.existingAbsoluteDirectory(
                  "cwd",
                  fileManager: fileManager
              ) else {
            return nil
        }

        self.command = command
        self.workingDirectory = directory
        self.authenticationToken = nil
    }

    /// 相等性表示「要执行的动作」相同，不比较传输层认证封装。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.command == rhs.command &&
            lhs.workingDirectory == rhs.workingDirectory
    }
}
