import Foundation

public struct CLIInvocation: Equatable, Sendable {
    public let command: CLICommand
    public let workingDirectory: URL

    public init(command: CLICommand, workingDirectory: URL) {
        self.command = command
        self.workingDirectory = workingDirectory
    }

    public var deepLink: URL? {
        guard workingDirectory.isFileURL,
              workingDirectory.path.hasPrefix("/") else {
            return nil
        }

        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: command.rawValue),
            URLQueryItem(name: "cwd", value: workingDirectory.path)
        ]
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
              queryItems.count == 2,
              queryItems.filter({ $0.name == "tool" }).count == 1,
              queryItems.filter({ $0.name == "cwd" }).count == 1,
              let tool = queryItems.first(where: { $0.name == "tool" })?.value,
              let command = CLICommand(rawValue: tool),
              let path = queryItems.first(where: { $0.name == "cwd" })?.value,
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

        self.command = command
        self.workingDirectory = directory
    }
}
