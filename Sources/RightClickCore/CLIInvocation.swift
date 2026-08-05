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
        if let authenticationToken {
            components.queryItems?.append(
                URLQueryItem(name: "token", value: authenticationToken)
            )
        }
        return components.url
    }

    public init?(
        deepLink: URL,
        fileManager: FileManager = .default
    ) {
        guard deepLink.scheme == AppConstants.deepLinkScheme,
              deepLink.host == "run",
              deepLink.user == nil,
              deepLink.password == nil,
              deepLink.port == nil,
              deepLink.fragment == nil,
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ),
              let queryItems = components.queryItems,
              queryItems.count == 2 || queryItems.count == 3,
              queryItems.allSatisfy({
                  $0.name == "tool" || $0.name == "cwd" || $0.name == "token"
              }),
              queryItems.filter({ $0.name == "tool" }).count == 1,
              queryItems.filter({ $0.name == "cwd" }).count == 1,
              queryItems.filter({ $0.name == "token" }).count <= 1,
              let tool = queryItems.first(where: { $0.name == "tool" })?.value,
              let command = CLICommand(rawValue: tool),
              let path = queryItems.first(where: { $0.name == "cwd" })?.value,
              path.hasPrefix("/") else {
            return nil
        }

        let authenticationToken = queryItems
            .first(where: { $0.name == "token" })?.value
        guard authenticationToken.map(
            ExtensionRequestTokenStore.isValidToken
        ) ?? true else {
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

        self.command = command
        self.workingDirectory = directory
        self.authenticationToken = authenticationToken
    }
}
