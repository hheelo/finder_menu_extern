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

/// 把用户可编辑的模板目录镜像到 Finder 扩展自己的容器。
/// 扩展只读取镜像；不跟随符号链接，也不接受子目录或超大文件。
public struct TemplateMirror {
    public static let maximumFileSize = 10 * 1_024 * 1_024

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func synchronize(
        existing: [CustomFileTemplate],
        sourceDirectory: URL,
        mirrorDirectory: URL
    ) throws -> [CustomFileTemplate] {
        try createPrivateDirectory(sourceDirectory)
        try createPrivateDirectory(mirrorDirectory)

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey
        ]
        let sources = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ).filter { url in
            guard FileCreator.isSafeFilename(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys) else {
                return false
            }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare(
            $1.lastPathComponent
        ) == .orderedAscending }

        guard sources.count <= CustomFileTemplate.validMenuSlots.count else {
            throw TemplateMirrorError.tooManyTemplates
        }

        let existingByFilename = Dictionary(
            existing.map { ($0.filename, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sourceNames = Set(sources.map(\.lastPathComponent))
        var usedSlots = Set(
            existing.filter { sourceNames.contains($0.filename) }.map(\.menuSlot)
        )
        var templates: [CustomFileTemplate] = []
        var expectedNames: Set<String> = []

        for source in sources {
            let values = try source.resourceValues(forKeys: keys)
            guard (values.fileSize ?? 0) <= Self.maximumFileSize else {
                throw TemplateMirrorError.templateTooLarge(source.lastPathComponent)
            }
            let filename = source.lastPathComponent
            expectedNames.insert(filename)
            let destination = mirrorDirectory.appendingPathComponent(filename)
            let mirroredValues = try? destination.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            let sourceDate = values.contentModificationDate
            let mirroredDate = mirroredValues?.contentModificationDate
            // Foundation 通过文件属性回写 Date 时可能损失亚毫秒精度；这种精度
            // 舍入不代表源文件变化，否则每次同步仍会原子替换镜像。
            let modificationDateMatches = sourceDate.flatMap { sourceDate in
                mirroredDate.map {
                    abs($0.timeIntervalSince(sourceDate)) < 0.001
                }
            } ?? false
            let isUnchanged = sourceDate != nil
                && mirroredValues?.fileSize == values.fileSize
                && modificationDateMatches

            // B1 之后每次宿主界面呈现都会同步。模板上限是 300 × 10 MB，
            // 未变化时不能继续全量读写。size + mtime 相同但内容不同的极端情况
            // 会被跳过；这里的目标正是避免为内容哈希读取全文，且镜像不是安全边界。
            if !isUnchanged {
                try Data(contentsOf: source).write(
                    to: destination,
                    options: .atomic
                )
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

            if let previous = existingByFilename[filename], previous.isValid {
                templates.append(previous)
            } else {
                guard let slot = CustomFileTemplate.validMenuSlots.first(where: {
                    !usedSlots.contains($0)
                }) else {
                    throw TemplateMirrorError.tooManyTemplates
                }
                usedSlots.insert(slot)
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
        return templates
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
