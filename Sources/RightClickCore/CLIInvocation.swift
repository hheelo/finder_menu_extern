import Foundation

public struct CLIInvocation: Equatable, SignedInvocation, Sendable {
    public static let deepLinkHost = "run"

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

    public var deepLinkQueryItems: [URLQueryItem]? {
        guard DeepLinkComponents.validWorkingDirectory(
            workingDirectory
        ) else { return nil }
        return [
            URLQueryItem(name: "tool", value: command.rawValue),
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
            semanticNames: ["tool", "cwd"]
        ),
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
