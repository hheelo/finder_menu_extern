import Foundation

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
