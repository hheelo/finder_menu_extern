import Foundation

/// 动态 CLI 深链只携带配置 ID 与工作目录；可执行名和参数永不进入 URL。
public struct ConfiguredCLIInvocation: Equatable, SignedInvocation, Sendable {
    public static let deepLinkHost = "run-configured"

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

    public var deepLinkQueryItems: [URLQueryItem]? {
        guard CLIProfile.isValidID(profileID),
              DeepLinkComponents.validWorkingDirectory(
                  workingDirectory
              ) else {
            return nil
        }
        return [
            URLQueryItem(name: "profile", value: profileID),
            URLQueryItem(name: "cwd", value: workingDirectory.path)
        ]
    }

    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard let components = DeepLinkComponents.authenticated(
            deepLink: deepLink,
            host: Self.deepLinkHost,
            semanticNames: ["profile", "cwd"]
        ),
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
