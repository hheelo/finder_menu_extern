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
    private static let maximumCreationAttempts = 8
    /// APFS/HFS 的 255 单元名称边界按 UTF-16 计数，而 Swift `String.count`
    /// 统计扩展字素簇。两者对 emoji 等字符并不相同：128 个 emoji 的
    /// `String.count` 是 128，但已占 256 个 UTF-16 单元，文件系统会拒绝。
    private static let maximumFilenameUTF16Count = 255
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
        for _ in 0..<Self.maximumCreationAttempts {
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
        for _ in 0..<Self.maximumCreationAttempts {
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
            && filename.utf16.count <= maximumFilenameUTF16Count
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
            let nextName = Self.filename(
                stem: stem,
                pathExtension: pathExtension,
                suffix: suffix
            )
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }

    /// 插入去重后缀时仍保持在文件系统的 255 单元名称上限内。优先裁短主文件名，
    /// 极端情况下才裁短扩展名；按 `Character` 截取，不会拆开组合字符。
    private static func filename(
        stem: String,
        pathExtension: String,
        suffix: Int
    ) -> String {
        let suffixText = " \(suffix)"
        var extensionText = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let stemBudget = maximumFilenameUTF16Count
            - suffixText.utf16.count
            - extensionText.utf16.count
        let fittedStem = prefix(
            of: stem,
            fittingUTF16Count: max(0, stemBudget)
        )

        let extensionBudget = maximumFilenameUTF16Count
            - fittedStem.utf16.count
            - suffixText.utf16.count
        extensionText = prefix(
            of: extensionText,
            fittingUTF16Count: max(0, extensionBudget)
        )
        return fittedStem + suffixText + extensionText
    }

    private static func prefix(
        of value: String,
        fittingUTF16Count limit: Int
    ) -> String {
        guard limit > 0 else { return "" }
        var used = 0
        return String(value.prefix { character in
            let count = String(character).utf16.count
            guard used + count <= limit else { return false }
            used += count
            return true
        })
    }
}
