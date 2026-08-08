import Foundation

public enum ClipboardText {
    public static func paths(for urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    public static func filenames(for urls: [URL]) -> String {
        urls.map(\.lastPathComponent).joined(separator: "\n")
    }

    public static func fileURLs(for urls: [URL]) -> String {
        urls.map { $0.standardizedFileURL.absoluteString }
            .joined(separator: "\n")
    }

    public static func shellQuotedPaths(for urls: [URL]) -> String {
        urls.map { ShellCommandBuilder.quote($0.path) }
            .joined(separator: "\n")
    }

    public static func parentPaths(for urls: [URL]) -> String {
        urls.map { $0.deletingLastPathComponent().path }
            .joined(separator: "\n")
    }
}
