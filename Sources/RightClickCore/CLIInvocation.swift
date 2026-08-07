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
        guard let components = DeepLinkComponents(
            deepLink: deepLink,
            host: "run",
            allowedNames: ["tool", "cwd", "token"]
        ),
              components.queryItems.count == 2 ||
                components.queryItems.count == 3,
              components.count(of: "token") <= 1,
              let tool = components.single("tool"),
              let command = CLICommand(rawValue: tool),
              let path = components.single("cwd"),
              path.hasPrefix("/") else {
            return nil
        }

        let authenticationToken = components.optionalSingle("token")
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
