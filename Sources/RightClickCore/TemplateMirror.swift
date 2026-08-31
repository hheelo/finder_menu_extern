import Darwin
import Foundation

public enum TemplateMirrorError: LocalizedError {
    case tooManyTemplates
    case templateTooLarge(String)

    public var errorDescription: String? {
        switch self {
        case .tooManyTemplates:
            L10n.text(
                "error.too_many_templates",
                fallback: "自定义模板数量已达到上限。"
            )
        case let .templateTooLarge(filename):
            L10n.format(
                "error.template_too_large",
                fallback: "模板“%@”超过 10 MB，未同步。",
                filename
            )
        }
    }
}

/// 一次模板镜像的可提交结果。单个超大文件是局部输入错误，不应阻断其他模板
/// 更新或过期镜像清理；调用方仍可用文件名向用户呈现警告。
public struct TemplateMirrorResult: Equatable, Sendable {
    public let templates: [CustomFileTemplate]
    public let skippedOversizedFilenames: [String]

    public init(
        templates: [CustomFileTemplate],
        skippedOversizedFilenames: [String] = []
    ) {
        self.templates = templates
        self.skippedOversizedFilenames = skippedOversizedFilenames
    }
}

/// 把用户可编辑的模板目录镜像到 Finder 扩展自己的容器。
/// 扩展只读取镜像；不跟随符号链接，也不接受子目录或超大文件。
public struct TemplateMirror {
    public static let maximumFileSize = 10 * 1_024 * 1_024

    private let fileManager: FileManager
    private let willOpenSource: (URL) -> Void

    private struct SourceTemplate {
        let url: URL
        let fileSize: Int
    }

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        willOpenSource = { _ in }
    }

    init(
        fileManager: FileManager = .default,
        willOpenSource: @escaping (URL) -> Void
    ) {
        self.fileManager = fileManager
        self.willOpenSource = willOpenSource
    }

    public func synchronize(
        existing: [CustomFileTemplate],
        sourceDirectory: URL,
        mirrorDirectory: URL
    ) throws -> TemplateMirrorResult {
        try createPrivateDirectory(sourceDirectory)
        try createPrivateDirectory(mirrorDirectory)

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ]
        let sources = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).compactMap { url -> SourceTemplate? in
            guard FileCreator.isSafeFilename(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys) else {
                return nil
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                return nil
            }
            return SourceTemplate(
                url: url,
                fileSize: values.fileSize ?? 0
            )
        }.sorted { $0.url.lastPathComponent.localizedStandardCompare(
            $1.url.lastPathComponent
        ) == .orderedAscending }

        let oversizedSources = sources.filter {
            $0.fileSize > Self.maximumFileSize
        }
        let eligibleSources = sources.filter {
            $0.fileSize <= Self.maximumFileSize
        }

        let maximumTemplateCount = CustomFileTemplate.validMenuSlots.count
        guard eligibleSources.count <= maximumTemplateCount else {
            throw TemplateMirrorError.tooManyTemplates
        }

        let existingByFilename = Dictionary(
            existing.map { ($0.filename, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sourceNames = Set(eligibleSources.map(\.url.lastPathComponent))
        let usedSlots = Set(
            existing.filter { sourceNames.contains($0.filename) }.map(\.menuSlot)
        )
        let availableSlots = CustomFileTemplate.validMenuSlots.filter {
            !usedSlots.contains($0)
        }
        var nextAvailableSlotIndex = availableSlots.startIndex
        var templates: [CustomFileTemplate] = []
        templates.reserveCapacity(eligibleSources.count)
        var expectedNames: Set<String> = []
        var oversizedFilenames = oversizedSources.map(\.url.lastPathComponent)

        for source in eligibleSources {
            let filename = source.url.lastPathComponent
            let destination = mirrorDirectory.appendingPathComponent(filename)
            let mirroredValues = try? destination.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                .contentModificationDateKey
            ])
            let mirrorIsSafe = mirroredValues?.isRegularFile == true
                && mirroredValues?.isSymbolicLink != true
            if mirroredValues != nil, !mirrorIsSafe {
                // 镜像是可再生的私有派生数据。异常目录或符号链接不能命中
                // “未变化”快路径，也不能永久阻断同名模板的后续同步。
                try fileManager.removeItem(at: destination)
            }
            willOpenSource(source.url)
            let sourceResult = try readSource(
                source.url,
                mirroredFileSize: mirrorIsSafe ? mirroredValues?.fileSize : nil,
                mirroredModificationDate: mirrorIsSafe
                    ? mirroredValues?.contentModificationDate
                    : nil
            )
            let sourceDate: Date?
            switch sourceResult {
            case .skipped:
                continue
            case .oversized:
                oversizedFilenames.append(filename)
                continue
            case let .unchanged(modificationDate):
                sourceDate = modificationDate
            case let .contents(contents, modificationDate):
                sourceDate = modificationDate
                try contents.write(to: destination, options: .atomic)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
                if let sourceDate {
                    // 原子写会使用当前时间；显式对齐后下一次才能命中快速路径。
                    try fileManager.setAttributes(
                        [.modificationDate: sourceDate],
                        ofItemAtPath: destination.path
                    )
                }
            }
            expectedNames.insert(filename)

            if let previous = existingByFilename[filename], previous.isValid {
                templates.append(previous)
            } else {
                guard nextAvailableSlotIndex < availableSlots.endIndex else {
                    throw TemplateMirrorError.tooManyTemplates
                }
                let slot = availableSlots[nextAvailableSlotIndex]
                availableSlots.formIndex(after: &nextAvailableSlotIndex)
                templates.append(
                    CustomFileTemplate(
                        id: UUID().uuidString.lowercased(),
                        title: filename,
                        filename: filename,
                        menuSlot: slot
                    )
                )
            }
        }

        for mirrored in try fileManager.contentsOfDirectory(
            at: mirrorDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where !expectedNames.contains(mirrored.lastPathComponent) {
            try fileManager.removeItem(at: mirrored)
        }
        return TemplateMirrorResult(
            templates: templates,
            skippedOversizedFilenames: oversizedFilenames
        )
    }

    /// 点击菜单后读取原始模板时复用同步阶段的同描述符校验：类型、大小与内容
    /// 都来自一次 `open(O_NOFOLLOW)`，避免“先看属性、再重新打开”之间被替换成
    /// 符号链接或超大文件，也避免把无界数据读进宿主主线程。
    public func loadContents(ofTemplateAt url: URL) throws -> Data? {
        willOpenSource(url)
        switch try readSource(
            url,
            mirroredFileSize: nil,
            mirroredModificationDate: nil
        ) {
        case .skipped:
            return nil
        case .oversized:
            throw TemplateMirrorError.templateTooLarge(url.lastPathComponent)
        case .unchanged:
            // 没有提供镜像元数据，因此该分支不可达；保守地拒绝空结果。
            return nil
        case let .contents(contents, _):
            return contents
        }
    }

    /// 打开、类型检查、大小检查和读取始终使用同一个描述符。`O_NOFOLLOW`
    /// 阻止目录枚举后被替换的符号链接；分块读取再次限制增长中的文件。
    private func readSource(
        _ url: URL,
        mirroredFileSize: Int?,
        mirroredModificationDate: Date?
    ) throws -> SourceReadResult {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if errno == ELOOP || errno == ENOENT { return .skipped }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { Darwin.close(descriptor) }

        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard status.st_mode & S_IFMT == S_IFREG else { return .skipped }
        guard status.st_size >= 0,
              status.st_size <= off_t(Self.maximumFileSize) else {
            return .oversized
        }

        let modificationDate = Date(
            timeIntervalSince1970:
                TimeInterval(status.st_mtimespec.tv_sec)
                + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        let modificationDateMatches = mirroredModificationDate.map {
            abs($0.timeIntervalSince(modificationDate)) < 0.001
        } ?? false
        // B1 之后每次宿主界面呈现都会同步。未变化时只做 open + fstat，
        // 不读取最多 10 MB 的全文。size + mtime 相同但内容不同仍是既有性能折中。
        if mirroredFileSize == Int(status.st_size), modificationDateMatches {
            return .unchanged(modificationDate: modificationDate)
        }

        let handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: false
        )
        var contents = Data()
        while contents.count <= Self.maximumFileSize {
            let remaining = Self.maximumFileSize - contents.count + 1
            guard let chunk = try handle.read(
                upToCount: min(64 * 1_024, remaining)
            ), !chunk.isEmpty else {
                return .contents(
                    contents,
                    modificationDate: modificationDate
                )
            }
            contents.append(chunk)
        }
        return .oversized
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}

private enum SourceReadResult {
    case skipped
    case oversized
    case unchanged(modificationDate: Date)
    case contents(Data, modificationDate: Date)
}
