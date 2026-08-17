import Foundation
import Testing
@testable import RightClickCore

struct MenuConfigurationCacheTests {
    @Test
    func unchangedStampReusesDecodedConfiguration() {
        let counter = LoadCounter()
        let url = URL(fileURLWithPath: "/tmp/menu.json")
        let stamp = FileStampValue.make(size: 10, date: 1)
        let cache = MenuConfigurationCache(
            load: { _ in
                counter.increment()
                return MenuConfiguration(collapseIntoSubmenu: true)
            },
            stamp: { _ in stamp }
        )

        #expect(cache.configuration(at: url).collapseIntoSubmenu)
        #expect(cache.configuration(at: url).collapseIntoSubmenu)
        #expect(counter.value == 1)
    }

    @Test
    func changedStampReloadsAndMissingFileFallsBackToDefault() {
        let state = StampState(FileStampValue.make(size: 10, date: 1))
        let counter = LoadCounter()
        let url = URL(fileURLWithPath: "/tmp/menu.json")
        let cache = MenuConfigurationCache(
            load: { _ in
                counter.increment()
                return MenuConfiguration(collapseIntoSubmenu: true)
            },
            stamp: { _ in state.value }
        )

        _ = cache.configuration(at: url)
        state.value = FileStampValue.make(size: 11, date: 2)
        _ = cache.configuration(at: url)
        state.value = nil

        #expect(cache.configuration(at: url) == .default)
        #expect(counter.value == 2)
    }

    @Test
    func atomicConfigurationReplacementIsVisibleOnTheNextRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("menu.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MenuConfigurationCache()

        try MenuConfigurationFile.saveForHost(
            MenuConfiguration(collapseIntoSubmenu: true),
            to: url
        )
        #expect(cache.configuration(at: url).collapseIntoSubmenu)

        try MenuConfigurationFile.saveForHost(
            MenuConfiguration(collapseIntoSubmenu: false),
            to: url
        )
        #expect(!cache.configuration(at: url).collapseIntoSubmenu)
    }
}

private enum FileStampValue {
    static func make(size: Int, date: TimeInterval) -> FileStamp {
        FileStamp(
            modificationDate: Date(timeIntervalSince1970: date),
            size: size
        )
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class StampState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: FileStamp?

    init(_ value: FileStamp?) { storedValue = value }

    var value: FileStamp? {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
