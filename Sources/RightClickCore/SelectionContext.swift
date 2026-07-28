import Foundation

public struct SelectionContext: Equatable, Sendable {
    public let selectedURLs: [URL]
    public let targetedURL: URL?

    public init(selectedURLs: [URL], targetedURL: URL?) {
        self.selectedURLs = selectedURLs
        self.targetedURL = targetedURL
    }

    public var effectiveURLs: [URL] {
        selectedURLs.isEmpty ? targetedURL.map { [$0] } ?? [] : selectedURLs
    }

    public var creationDirectory: URL? {
        if selectedURLs.isEmpty {
            return directoryRepresented(by: targetedURL)
        }

        if selectedURLs.count == 1,
           let selected = selectedURLs.first,
           selected.hasDirectoryPath {
            return selected
        }

        return selectedURLs.first?.deletingLastPathComponent()
    }

    public var workingDirectory: URL? {
        guard let first = effectiveURLs.first else { return nil }
        return first.hasDirectoryPath ? first : first.deletingLastPathComponent()
    }

    private func directoryRepresented(by url: URL?) -> URL? {
        guard let url else { return nil }
        return url.hasDirectoryPath ? url : url.deletingLastPathComponent()
    }
}
