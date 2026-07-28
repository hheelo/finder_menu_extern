import Foundation

public struct ActionRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let action: RightClickAction
    public let selectedURLs: [URL]
    public let targetedURL: URL?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        action: RightClickAction,
        selectedURLs: [URL],
        targetedURL: URL?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.selectedURLs = selectedURLs
        self.targetedURL = targetedURL
        self.createdAt = createdAt
    }

    public var deepLink: URL? {
        URL(string: "\(AppConstants.deepLinkScheme)://perform?id=\(id.uuidString)")
    }
}
