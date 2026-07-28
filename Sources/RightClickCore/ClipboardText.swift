import Foundation

public enum ClipboardText {
    public static func paths(for urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }

    public static func filenames(for urls: [URL]) -> String {
        urls.map(\.lastPathComponent).joined(separator: "\n")
    }
}
