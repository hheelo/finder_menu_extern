import Foundation

public enum FileCreatorError: LocalizedError {
    case destinationIsNotDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case let .destinationIsNotDirectory(url):
            "无法在“\(url.path)”中新建文件：目标不是文件夹。"
        }
    }
}

public struct FileCreator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func create(_ template: FileTemplate, in directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileCreatorError.destinationIsNotDirectory(directory)
        }

        let destination = availableURL(
            named: template.preferredFilename,
            in: directory
        )
        try Data(template.initialContents.utf8).write(
            to: destination,
            options: .withoutOverwriting
        )
        return destination
    }

    private func availableURL(named filename: String, in directory: URL) -> URL {
        let original = URL(fileURLWithPath: filename)
        let stem = original.deletingPathExtension().lastPathComponent
        let pathExtension = original.pathExtension

        var candidate = directory.appendingPathComponent(filename)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(pathExtension)"
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }
}
