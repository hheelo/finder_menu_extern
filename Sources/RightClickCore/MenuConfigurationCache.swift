import Foundation

/// Finder 配置写入使用原子替换，因此修改时间或文件大小变化即可使缓存失效。
/// 文件戳只避免重复解码；文件不存在、不可读或版本未知时仍由配置加载器回退默认值。
public struct FileStamp: Equatable, Sendable {
    public let modificationDate: Date
    public let size: Int

    public init(modificationDate: Date, size: Int) {
        self.modificationDate = modificationDate
        self.size = size
    }

    public init?(
        url: URL,
        fileManager: FileManager = .default
    ) {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ), let modificationDate = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue else {
            return nil
        }
        self.modificationDate = modificationDate
        self.size = size
    }
}

/// 单槽配置缓存。内部加锁，不依赖 FinderSync 回调当前恰好都在主线程的事实。
public final class MenuConfigurationCache: @unchecked Sendable {
    public typealias Loader = (URL) -> MenuConfiguration
    public typealias StampReader = (URL) -> FileStamp?

    private let load: Loader
    private let stamp: StampReader
    private let lock = NSLock()
    private var cached: (stamp: FileStamp, value: MenuConfiguration)?

    public convenience init(fileManager: FileManager = .default) {
        self.init(
            load: { MenuConfigurationFile.load(from: $0) },
            stamp: { FileStamp(url: $0, fileManager: fileManager) }
        )
    }

    public init(
        load: @escaping Loader,
        stamp: @escaping StampReader
    ) {
        self.load = load
        self.stamp = stamp
    }

    public func configuration(at url: URL?) -> MenuConfiguration {
        guard let url else { return .default }
        return lock.withLock {
            guard let currentStamp = stamp(url) else {
                cached = nil
                return .default
            }
            if let cached, cached.stamp == currentStamp {
                return cached.value
            }
            let value = load(url)
            cached = (currentStamp, value)
            return value
        }
    }
}
