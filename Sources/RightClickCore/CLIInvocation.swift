import Foundation

public struct CLIInvocation: Equatable, Sendable {
    public let command: CLICommand
    public let workingDirectory: URL

    public init(command: CLICommand, workingDirectory: URL) {
        self.command = command
        self.workingDirectory = workingDirectory
    }

    public var deepLink: URL? {
        var components = URLComponents()
        components.scheme = AppConstants.deepLinkScheme
        components.host = "run"
        components.queryItems = [
            URLQueryItem(name: "tool", value: command.rawValue),
            URLQueryItem(name: "cwd", value: workingDirectory.path)
        ]
        return components.url
    }

    public init?(deepLink: URL) {
        guard deepLink.scheme == AppConstants.deepLinkScheme,
              deepLink.host == "run",
              let components = URLComponents(
                  url: deepLink,
                  resolvingAgainstBaseURL: false
              ),
              let tool = components.queryItems?
                  .first(where: { $0.name == "tool" })?.value,
              let command = CLICommand(rawValue: tool),
              let path = components.queryItems?
                  .first(where: { $0.name == "cwd" })?.value,
              !path.isEmpty else {
            return nil
        }

        self.command = command
        self.workingDirectory = URL(
            fileURLWithPath: path,
            isDirectory: true
        )
    }
}
