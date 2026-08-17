import Foundation

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
