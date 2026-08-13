import Foundation

/// 动态 CLI 深链只携带配置 ID 与工作目录；可执行名和参数永不进入 URL。
public struct ConfiguredCLIInvocation: Equatable, Sendable {
    public let profileID: String
    public let workingDirectory: URL
    public let authenticationToken: String?

    public init(
        profileID: String,
        workingDirectory: URL,
        authenticationToken: String? = nil
    ) {
        self.profileID = profileID
        self.workingDirectory = workingDirectory
        self.authenticationToken = authenticationToken
    }

    public var deepLink: URL? {
        deepLink(now: Date(), nonce: UUID().uuidString)
    }

    public func deepLink(now: Date, nonce: String) -> URL? {
        guard CLIProfile.isValidID(profileID),
              workingDirectory.isFileURL,
              workingDirectory.path.hasPrefix("/"),
              authenticationToken.map(
                  ExtensionRequestTokenStore.isValidToken
              ) ?? true else {
            return nil
        }
        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run-configured"
        components.queryItems = [
            URLQueryItem(name: "profile", value: profileID),
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
            host: "run-configured",
            allowedNames: [
                "profile", "cwd", "v", "ts", "nonce", "sig"
            ]
        ), DeepLinkSignature.authentication(in: deepLink) != nil,
              let profileID = components.single("profile"),
              CLIProfile.isValidID(profileID),
              let directory = components.existingAbsoluteDirectory(
                  "cwd",
                  fileManager: fileManager
              ) else {
            return nil
        }
        self.profileID = profileID
        self.workingDirectory = directory
        authenticationToken = nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.profileID == rhs.profileID
            && lhs.workingDirectory == rhs.workingDirectory
    }
}
