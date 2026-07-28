import Foundation

public enum RequestStoreError: LocalizedError {
    case sharedContainerUnavailable
    case requestNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            "无法访问 App Group 共享目录。请检查签名与 App Group 配置。"
        case let .requestNotFound(id):
            "找不到操作请求：\(id.uuidString)"
        }
    }
}

public struct RequestStore {
    private let rootURL: URL?
    private let fileManager: FileManager

    public init(
        rootURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier
        ),
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func enqueue(_ request: ActionRequest) throws {
        let directory = try requestsDirectory()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(request)
        try data.write(to: fileURL(for: request.id, in: directory), options: .atomic)
    }

    public func take(id: UUID) throws -> ActionRequest {
        let directory = try requestsDirectory()
        let url = fileURL(for: id, in: directory)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RequestStoreError.requestNotFound(id)
        }
        let request = try JSONDecoder().decode(
            ActionRequest.self,
            from: Data(contentsOf: url)
        )
        try fileManager.removeItem(at: url)
        return request
    }

    private func requestsDirectory() throws -> URL {
        guard let rootURL else {
            throw RequestStoreError.sharedContainerUnavailable
        }
        return rootURL.appendingPathComponent(
            AppConstants.requestDirectoryName,
            isDirectory: true
        )
    }

    private func fileURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
