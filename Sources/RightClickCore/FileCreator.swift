import Foundation

public enum FileCreatorError: LocalizedError {
    case destinationIsNotDirectory(URL)
    case invalidFilename(String)

    public var errorDescription: String? {
        switch self {
        case let .destinationIsNotDirectory(url):
            L10n.format(
                "error.destination_not_directory",
                fallback: "无法在“%@”中新建文件：目标不是文件夹。",
                url.path
            )
        case let .invalidFilename(filename):
            L10n.format(
                "error.invalid_filename",
                fallback: "无法使用“%@”作为文件名。",
                filename
            )
        }
    }
}

public struct FileCreator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func create(
        _ template: FileTemplate,
        override: TemplateOverride? = nil,
        in directory: URL
    ) throws -> URL {
        let sanitizedOverride = override?.sanitized
        return try create(
            contents: (sanitizedOverride?.resolvedEncoding ?? .utf8)
                .encode(template.initialContents),
            preferredFilename: sanitizedOverride?.filename
                ?? template.preferredFilename,
            in: directory
        )
    }

    @discardableResult
    public func create(
        contents: Data,
        preferredFilename: String,
        in directory: URL
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileCreatorError.destinationIsNotDirectory(directory)
        }
        guard Self.isSafeFilename(preferredFilename) else {
            throw FileCreatorError.invalidFilename(preferredFilename)
        }

        // 检查空闲名称与实际写入之间存在竞争窗口（连续点击或多个 Finder
        // 进程即可触发）。保留 .withoutOverwriting 这条数据安全保证，并在
        // 名称刚被占用时重新寻找；其他错误立即上抛。
        var lastConflict: Error?
        for _ in 0..<8 {
            let destination = availableURL(
                named: preferredFilename,
                in: directory
            )
            do {
                try contents.write(
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

    @discardableResult
    public func createDirectory(
        preferredName: String = L10n.text(
            "file.untitled_folder",
            fallback: "未命名文件夹"
        ),
        in directory: URL
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileCreatorError.destinationIsNotDirectory(directory)
        }
        guard Self.isSafeFilename(preferredName) else {
            throw FileCreatorError.invalidFilename(preferredName)
        }

        var lastConflict: Error?
        for _ in 0..<8 {
            let destination = availableURL(named: preferredName, in: directory)
            do {
                try fileManager.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
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

    public static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename.count <= 255
            && filename != "."
            && filename != ".."
            && !filename.contains("/")
            && !filename.contains("\0")
            && !filename.contains("\n")
            && !filename.contains("\r")
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
