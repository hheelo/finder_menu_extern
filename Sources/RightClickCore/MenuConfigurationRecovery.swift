import Foundation

public enum MenuConfigurationLoadFailure: Equatable, Sendable {
    case unreadable
    case corrupted
    case unsupportedVersion(Int)
}

public enum MenuConfigurationLoadResult: Equatable, Sendable {
    case loaded(MenuConfiguration)
    case missing
    case migrated(MenuConfiguration, fromVersion: Int)
    case invalid(MenuConfigurationLoadFailure, originalData: Data?)

    /// Finder 必须始终拿到可显示的配置；详细失败语义只由宿主恢复流程处理。
    public var configuration: MenuConfiguration {
        switch self {
        case let .loaded(configuration),
             let .migrated(configuration, _):
            configuration
        case .missing, .invalid:
            .default
        }
    }

    public var canPersist: Bool {
        switch self {
        case .loaded, .missing, .migrated: true
        case .invalid: false
        }
    }

    public var failure: MenuConfigurationLoadFailure? {
        guard case let .invalid(failure, _) = self else { return nil }
        return failure
    }

    public var originalData: Data? {
        guard case let .invalid(_, data) = self else { return nil }
        return data
    }
}

struct MenuConfigurationVersionEnvelope: Decodable {
    let version: Int
}

public enum MenuConfigurationMigrationError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidData
}

/// 菜单配置的逐版本迁移入口。当前只有 v1，因此暂时没有转换步骤；以后提升
/// `currentVersion` 时必须在这里按 1→2→3 逐级迁移，禁止跨版本猜测字段。
enum MenuConfigurationMigrator {
    static func decode(
        _ data: Data,
        fromVersion version: Int,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> MenuConfiguration {
        guard version == MenuConfiguration.currentVersion else {
            throw MenuConfigurationMigrationError.unsupportedVersion(version)
        }
        guard let configuration = try? decoder.decode(
            MenuConfiguration.self,
            from: data
        ), configuration.version == MenuConfiguration.currentVersion else {
            throw MenuConfigurationMigrationError.invalidData
        }
        return configuration
    }
}

public enum MenuConfigurationBackup {
    public static let maximumBackupCount = 5

    /// 只备份已经成功读取的原始字节；读取失败时不能假装已经保护了配置。
    @discardableResult
    public static func preserveInvalidConfiguration(
        _ result: MenuConfigurationLoadResult,
        sourceURL: URL,
        date: Date = Date(),
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard let data = result.originalData else { return nil }
        return try preserve(
            data,
            sourceURL: sourceURL,
            label: "recovery",
            date: date,
            identifier: identifier,
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func preserveExistingConfiguration(
        at sourceURL: URL,
        date: Date = Date(),
        identifier: UUID = UUID(),
        fileManager: FileManager = .default
    ) throws -> URL? {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }
        let data = try Data(contentsOf: sourceURL)
        return try preserve(
            data,
            sourceURL: sourceURL,
            label: "settings",
            date: date,
            identifier: identifier,
            fileManager: fileManager
        )
    }

    private static func preserve(
        _ data: Data,
        sourceURL: URL,
        label: String,
        date: Date,
        identifier: UUID,
        fileManager: FileManager
    ) throws -> URL {
        let directory = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let timestamp = ISO8601DateFormatter().string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        let filename = "menu-\(timestamp)-\(label)-\(identifier.uuidString.lowercased()).json"
        let destination = directory.appendingPathComponent(filename)
        // Foundation 在部分系统上不允许 `.atomic` 与 `.withoutOverwriting`
        // 组合使用。文件名包含 UUID，使用原子写即可避免半份备份。
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        try prune(directory: directory, keeping: maximumBackupCount, fileManager: fileManager)
        return destination
    }

    private static func prune(
        directory: URL,
        keeping limit: Int,
        fileManager: FileManager
    ) throws {
        let backups = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted {
            // 文件名以固定 ISO-8601 时间戳开头；按名称排序不依赖文件系统
            // mtime 精度，也不会在快速连续备份时随机删掉最新文件。
            $0.lastPathComponent < $1.lastPathComponent
        }
        for stale in backups.dropLast(limit) {
            try fileManager.removeItem(at: stale)
        }
    }
}

public enum MenuConfigurationTransferError: LocalizedError, Equatable {
    case documentTooLarge
    case unsupportedFormat
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .documentTooLarge:
            L10n.text(
                "error.settings_document_too_large",
                fallback: "设置文件超过 2 MB 上限。"
            )
        case .unsupportedFormat:
            L10n.text(
                "error.settings_document_unsupported",
                fallback: "设置文件格式版本不受支持。"
            )
        case .invalidConfiguration:
            L10n.text(
                "error.settings_document_invalid",
                fallback: "设置文件内容无效或已损坏。"
            )
        }
    }
}

/// 可移植设置文档只包含可安全跨机器复用的菜单配置。终端选择仍由宿主设置持有，
/// 自定义模板文件仍留在模板目录；导入时保留这两类本机状态，避免产生悬空模板。
public enum MenuConfigurationTransfer {
    public static let fileExtension = "rightclick-settings.json"
    public static let maximumDocumentSize = 2 * 1_024 * 1_024

    private struct Document: Codable {
        let formatVersion: Int
        let configuration: MenuConfiguration
    }

    public static func exportData(
        _ configuration: MenuConfiguration
    ) throws -> Data {
        var portable = configuration.sanitized
        portable.version = MenuConfiguration.currentVersion
        portable.terminalProfileID = nil
        portable.customTemplates = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(
            formatVersion: 1,
            configuration: portable
        ))
        guard data.count <= maximumDocumentSize else {
            throw MenuConfigurationTransferError.documentTooLarge
        }
        return data
    }

    public static func importData(
        _ data: Data,
        preservingLocalStateFrom current: MenuConfiguration
    ) throws -> MenuConfiguration {
        guard data.count <= maximumDocumentSize else {
            throw MenuConfigurationTransferError.documentTooLarge
        }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw MenuConfigurationTransferError.invalidConfiguration
        }
        guard document.formatVersion == 1 else {
            throw MenuConfigurationTransferError.unsupportedFormat
        }
        guard document.configuration.version == MenuConfiguration.currentVersion else {
            throw MenuConfigurationTransferError.invalidConfiguration
        }
        var imported = document.configuration.sanitized
        imported.terminalProfileID = current.terminalProfileID
        imported.customTemplates = current.customTemplates
        return imported
    }
}
