import Foundation

public enum LocalActionLogFile {
    private static let supportDirectoryName = "RightClick"
    private static let filename = "action-log.json"
    private static let sessionMarkerFilename = "host-session.active"

    public static func hostURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func extensionURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func extensionHostURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        MenuConfigurationFile.hostURL(homeDirectory: homeDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func sessionMarkerURL(for hostLogURL: URL) -> URL {
        hostLogURL.deletingLastPathComponent()
            .appendingPathComponent(sessionMarkerFilename, isDirectory: false)
    }
}
