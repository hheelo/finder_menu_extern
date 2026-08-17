import Foundation

/// 本地动作日志只接受封闭的稳定标识，调用方无法把路径、文件名、命令参数或
/// 深链 URL 塞进记录。导出的日志因此可以直接附到 Issue，而不泄露操作目标。
public enum LocalActionLogSource: String, Codable, Sendable {
    case host
    case finderExtension = "finder-extension"
}

public enum LocalActionName: String, Codable, Sendable {
    case applicationSession = "application-session"
    case extensionErrorReport = "extension-error-report"
    case unknownMenuAction = "unknown-menu-action"
    case configuredCLI = "configured-cli"
    case customTemplate = "custom-template"
    case copyPath
    case copyFilename
    case copyFileURL
    case copyShellPath
    case copyParentPath
    case copyRelativePath
    case openInVSCode
    case openInCodex
    case openInTerminal
    case runCodexCLI
    case runClaudeCode
    case openInCursor
    case openInZed
    case openInSublimeText
    case openInXcode
    case openInJetBrains
    case openInDefaultApplication
    case createTextFile = "createFile(text)"
    case createMarkdownFile = "createFile(markdown)"
    case createPythonFile = "createFile(python)"
    case createShellFile = "createFile(shell)"
    case createHTMLFile = "createFile(html)"
    case createJSONFile = "createFile(json)"
    case createCSVFile = "createFile(csv)"
    case createFolder
    case createFileFromClipboard

    public init(_ action: RightClickAction) {
        switch action {
        case .copyPath: self = .copyPath
        case .copyFilename: self = .copyFilename
        case .copyFileURL: self = .copyFileURL
        case .copyShellPath: self = .copyShellPath
        case .copyParentPath: self = .copyParentPath
        case .copyRelativePath: self = .copyRelativePath
        case .openInVSCode: self = .openInVSCode
        case .openInCodex: self = .openInCodex
        case .openInTerminal: self = .openInTerminal
        case .runCodexCLI: self = .runCodexCLI
        case .runClaudeCode: self = .runClaudeCode
        case .openInCursor: self = .openInCursor
        case .openInZed: self = .openInZed
        case .openInSublimeText: self = .openInSublimeText
        case .openInXcode: self = .openInXcode
        case .openInJetBrains: self = .openInJetBrains
        case .openInDefaultApplication: self = .openInDefaultApplication
        case let .createFile(template):
            switch template {
            case .text: self = .createTextFile
            case .markdown: self = .createMarkdownFile
            case .python: self = .createPythonFile
            case .shell: self = .createShellFile
            case .html: self = .createHTMLFile
            case .json: self = .createJSONFile
            case .csv: self = .createCSVFile
            }
        case .createFolder: self = .createFolder
        case .createFileFromClipboard: self = .createFileFromClipboard
        }
    }

    public init(_ command: CLICommand) {
        switch command {
        case .codex: self = .runCodexCLI
        case .claude: self = .runClaudeCode
        }
    }

    public init(opening application: ExternalApplication) {
        switch application.identifier {
        case ExternalApplication.visualStudioCode.identifier:
            self = .openInVSCode
        case ExternalApplication.codex.identifier:
            self = .openInCodex
        case ExternalApplication.cursor.identifier:
            self = .openInCursor
        case ExternalApplication.zed.identifier:
            self = .openInZed
        case ExternalApplication.sublimeText.identifier:
            self = .openInSublimeText
        case ExternalApplication.xcode.identifier:
            self = .openInXcode
        case ExternalApplication.jetBrains.identifier:
            self = .openInJetBrains
        default:
            self = .openInDefaultApplication
        }
    }
}

public enum LocalActionResult: String, Codable, Sendable {
    case started
    case received
    case forwarded
    case succeeded
    case failed
}

public enum LocalActionErrorCategory: String, Codable, Sendable {
    case invalidRequest = "invalid-request"
    case invalidTarget = "invalid-target"
    case invalidWorkingDirectory = "invalid-working-directory"
    case tooManyTargets = "too-many-targets"
    case authenticationUnavailable = "authentication-unavailable"
    case configurationUnavailable = "configuration-unavailable"
    case hostApplicationUnavailable = "host-application-unavailable"
    case applicationNotFound = "application-not-found"
    case commandUnavailable = "command-unavailable"
    case unsupportedTerminal = "unsupported-terminal"
    case applicationLaunchFailed = "application-launch-failed"
    case executionFailed = "execution-failed"
    case fileSystem = "file-system"
    case extensionReported = "extension-reported"
    case unexpectedTermination = "unexpected-termination"
    case cancelled
    case unknown

    public init(_ error: Error) {
        if let finderError = error as? FinderActionError {
            switch finderError {
            case .invalidTarget: self = .invalidTarget
            case .invalidWorkingDirectory: self = .invalidWorkingDirectory
            case .tooManyOpenTargets: self = .tooManyTargets
            case .authenticationUnavailable: self = .authenticationUnavailable
            case .configurationUnavailable: self = .configurationUnavailable
            case .hostApplicationUnavailable: self = .hostApplicationUnavailable
            }
        } else if error is FileCreatorError || error is CocoaError {
            self = .fileSystem
        } else if error is CancellationError {
            self = .cancelled
        } else {
            self = .unknown
        }
    }
}

public struct LocalActionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let source: LocalActionLogSource
    public let action: LocalActionName
    public let result: LocalActionResult
    public let errorCategory: LocalActionErrorCategory?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        source: LocalActionLogSource,
        action: LocalActionName,
        result: LocalActionResult,
        errorCategory: LocalActionErrorCategory? = nil
    ) {
        self.id = id
        self.date = date
        self.source = source
        self.action = action
        self.result = result
        self.errorCategory = errorCategory
    }
}

/// 小型、有界的 JSON 日志。宿主和扩展使用不同文件，避免跨进程原子替换竞争；
/// 宿主导出时再合并。任何读写失败都不能影响 Finder 动作本身。
public final class LocalActionLogStore: @unchecked Sendable {
    public static let defaultMaximumRecordCount = 200

    typealias Writer = @Sendable (
        [LocalActionRecord],
        URL,
        FileManager
    ) throws -> Void

    public let fileURL: URL?
    private let maximumRecordCount: Int
    private let fileManager: FileManager
    private let lock = NSLock()
    private let persistenceLock = NSLock()
    private let persistenceDelay: Duration
    private let flushThreshold: Int
    private let write: Writer
    private var current: [LocalActionRecord]
    private var unpersistedRecordCount = 0
    private var pendingFlush: Task<Void, Never>?

    public convenience init(
        fileURL: URL?,
        maximumRecordCount: Int = defaultMaximumRecordCount,
        fileManager: FileManager = .default
    ) {
        self.init(
            fileURL: fileURL,
            maximumRecordCount: maximumRecordCount,
            fileManager: fileManager,
            persistenceDelay: .milliseconds(200),
            flushThreshold: 10,
            write: { try Self.save($0, to: $1, fileManager: $2) }
        )
    }

    init(
        fileURL: URL?,
        maximumRecordCount: Int = defaultMaximumRecordCount,
        fileManager: FileManager = .default,
        persistenceDelay: Duration,
        flushThreshold: Int,
        write: @escaping Writer
    ) {
        self.fileURL = fileURL
        self.maximumRecordCount = max(1, maximumRecordCount)
        self.fileManager = fileManager
        self.persistenceDelay = persistenceDelay
        self.flushThreshold = max(1, flushThreshold)
        self.write = write
        var loaded = fileURL.map {
            Self.load(from: $0, fileManager: fileManager)
        } ?? []
        if loaded.count > self.maximumRecordCount {
            loaded.removeFirst(loaded.count - self.maximumRecordCount)
        }
        current = loaded
    }

    public func append(_ record: LocalActionRecord) {
        guard fileURL != nil else { return }
        lock.withLock {
            current.append(record)
            if current.count > maximumRecordCount {
                current.removeFirst(current.count - maximumRecordCount)
            }
            unpersistedRecordCount += 1
            scheduleFlush(immediately: unpersistedRecordCount >= flushThreshold)
        }
    }

    public func records() -> [LocalActionRecord] {
        lock.withLock { current }
    }

    /// 退出、导出或测试需要立刻观察文件时显式冲刷。写失败保持静默，不能反向
    /// 影响 Finder 动作；下一次 append 会再次安排落盘。
    public func flush() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            defer { pendingFlush = nil }
            return pendingFlush
        }
        task?.cancel()
        persistPendingRecords()
    }

    public static func load(
        from fileURL: URL,
        fileManager: FileManager = .default
    ) -> [LocalActionRecord] {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: fileURL.path
        ), let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= 1_048_576,
              let data = try? Data(contentsOf: fileURL),
              let container = try? JSONDecoder.localActionLog.decode(
                  Container.self,
                  from: data
              ), container.version == Container.currentVersion else {
            return []
        }
        return container.records
    }

    private static func save(
        _ records: [LocalActionRecord],
        to fileURL: URL,
        fileManager: FileManager
    ) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard fileManager.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try JSONEncoder.localActionLog.encode(
            Container(records: records)
        ).write(to: fileURL, options: .atomic)
    }

    private func scheduleFlush(immediately: Bool) {
        pendingFlush?.cancel()
        let delay = immediately ? Duration.zero : persistenceDelay
        pendingFlush = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.persistPendingRecords()
        }
    }

    private func persistPendingRecords() {
        persistenceLock.withLock {
            let snapshot = lock.withLock {
                (records: current, pendingCount: unpersistedRecordCount)
            }
            guard snapshot.pendingCount > 0, let fileURL else { return }
            do {
                try write(snapshot.records, fileURL, fileManager)
                lock.withLock {
                    unpersistedRecordCount = max(
                        0,
                        unpersistedRecordCount - snapshot.pendingCount
                    )
                }
            } catch {
                // 本地诊断日志是旁路能力；失败不能改变用户动作的结果。
            }
        }
    }

    private struct Container: Codable {
        static let currentVersion = 1
        let version: Int
        let records: [LocalActionRecord]

        init(records: [LocalActionRecord]) {
            version = Self.currentVersion
            self.records = records
        }
    }
}

public final class LocalActionSessionTracker: @unchecked Sendable {
    private let store: LocalActionLogStore
    private let markerURL: URL?
    private let fileManager: FileManager
    private let lock = NSLock()
    private var isActive = false

    public init(
        store: LocalActionLogStore,
        markerURL: URL?,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.markerURL = markerURL
        self.fileManager = fileManager
    }

    /// 残留标记只能证明上次没有走正常终止回调，可能是崩溃、强制退出或断电；
    /// 记录为 unexpected-termination，不伪装成已经确认的 crash report。
    public func begin(date: Date = Date()) {
        lock.withLock {
            guard !isActive else { return }
            isActive = true
            if let markerURL,
               fileManager.fileExists(atPath: markerURL.path) {
                store.append(LocalActionRecord(
                    date: date,
                    source: .host,
                    action: .applicationSession,
                    result: .failed,
                    errorCategory: .unexpectedTermination
                ))
            }
            writeMarker()
            store.append(LocalActionRecord(
                date: date,
                source: .host,
                action: .applicationSession,
                result: .started
            ))
        }
    }

    public func end(date: Date = Date()) {
        lock.withLock {
            guard isActive else { return }
            if let markerURL {
                try? fileManager.removeItem(at: markerURL)
            }
            store.append(LocalActionRecord(
                date: date,
                source: .host,
                action: .applicationSession,
                result: .succeeded
            ))
            store.flush()
            isActive = false
        }
    }

    private func writeMarker() {
        guard let markerURL else { return }
        let directory = markerURL.deletingLastPathComponent()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? Data("active\n".utf8).write(to: markerURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: markerURL.path
        )
    }
}

public enum LocalActionLogFile {
    private static let supportDirectoryName = "RightClick"
    private static let filename = "action-log.json"
    private static let sessionMarkerFilename = "host-session.active"

    public static func hostURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func extensionURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func extensionHostURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        MenuConfigurationFile.hostURL(homeDirectory: homeDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func sessionMarkerURL(for hostLogURL: URL) -> URL {
        hostLogURL.deletingLastPathComponent()
            .appendingPathComponent(sessionMarkerFilename, isDirectory: false)
    }
}

public enum LocalActionLogReport {
    public static func make(
        hostRecords: [LocalActionRecord],
        extensionRecords: [LocalActionRecord],
        appVersion: String,
        generatedAt: Date = Date(),
        maximumRecordCount: Int = LocalActionLogStore.defaultMaximumRecordCount
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let records = (hostRecords + extensionRecords)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    let leftRank = resultSortRank(lhs.result)
                    let rightRank = resultSortRank(rhs.result)
                    if leftRank != rightRank { return leftRank < rightRank }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.date < rhs.date
            }
            .suffix(max(1, maximumRecordCount))
        var lines = [
            "RightClick Local Action Log",
            "Version: \(appVersion)",
            "Generated: \(formatter.string(from: generatedAt))",
            "Privacy: action names, outcomes, and error categories only; no paths, filenames, commands, arguments, or deep-link URLs.",
            "Timestamp\tSource\tAction\tResult\tError category"
        ]
        lines += records.map { record in
            [
                formatter.string(from: record.date),
                record.source.rawValue,
                record.action.rawValue,
                record.result.rawValue,
                record.errorCategory?.rawValue ?? "-"
            ].joined(separator: "\t")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func resultSortRank(_ result: LocalActionResult) -> Int {
        switch result {
        case .started, .received: 0
        case .forwarded, .succeeded, .failed: 1
        }
    }
}

private extension JSONEncoder {
    static var localActionLog: JSONEncoder {
        let encoder = JSONEncoder()
        // `.iso8601` 会把同一秒内的 received / outcome 压成相同时间，导出排序
        // 可能反转。毫秒足以保留一次 Finder 点击的阶段顺序。
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var localActionLog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
