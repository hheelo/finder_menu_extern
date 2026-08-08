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

        // 检查空闲名称与实际写入之间存在竞争窗口（连续点击或多个 Finder
        // 进程即可触发）。保留 .withoutOverwriting 这条数据安全保证，并在
        // 名称刚被占用时重新寻找；其他错误立即上抛。
        var lastConflict: Error?
        for _ in 0..<8 {
            let destination = availableURL(
                named: template.preferredFilename,
                in: directory
            )
            do {
                try Data(template.initialContents.utf8).write(
                    to: destination,
                    options: .withoutOverwriting
                )
                return destination
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain &&
                    error.code == NSFileWriteFileExistsError {
                lastConflict = error
            }
        }
        throw lastConflict ?? CocoaError(.fileWriteFileExists)
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
