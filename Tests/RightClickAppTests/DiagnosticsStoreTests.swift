import Foundation
import RightClickCore
import Testing

@MainActor
struct DiagnosticsStoreTests {
    @Test
    func freshCacheAvoidsCollectionAndUsesLiveExtensionState() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { fixture.now },
            collector: { enabled in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await store.collect(extensionEnabled: false, force: true)
        let cached = await store.collect(extensionEnabled: true, force: false)

        #expect(collections == 1)
        #expect(cached?.first?.id == "extension")
        #expect(cached?.first?.passed == true)
    }

    @Test
    func staleCacheIsShownThenRefreshed() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var currentDate = fixture.now
        var detail = "first"
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { currentDate },
            collector: { enabled in
                [
                    DiagnosticItem(
                        id: "extension",
                        title: "Finder 扩展",
                        passed: enabled,
                        detail: enabled ? "已启用" : "未启用"
                    ),
                    DiagnosticItem(
                        id: "codex",
                        title: "Codex CLI",
                        passed: true,
                        detail: detail
                    )
                ]
            }
        )
        _ = await store.collect(extensionEnabled: false, force: true)
        currentDate.addTimeInterval(DiagnosticsStore.cacheLifetime + 1)
        detail = "second"

        #expect(store.cached(extensionEnabled: false)?[1].detail == "first")
        let refreshed = await store.collect(
            extensionEnabled: false,
            force: false
        )
        #expect(refreshed?[1].detail == "second")
    }

    @Test
    func futureDatedCacheIsNotTreatedAsFresh() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var currentDate = fixture.now
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { currentDate },
            collector: { enabled in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await store.collect(extensionEnabled: false, force: true)
        currentDate.addTimeInterval(-1)

        #expect(!store.hasFreshCache)
        _ = await store.collect(extensionEnabled: false, force: false)
        #expect(collections == 2)
    }

    @Test
    func malformedCacheFallsBackToCollection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.settings.cachedDiagnostics = Data("not-json".utf8)
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { fixture.now },
            collector: { enabled in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        #expect(store.cached(extensionEnabled: false) == nil)
        #expect(!store.hasFreshCache)
        _ = await store.collect(extensionEnabled: false, force: false)
        #expect(collections == 1)
    }

    @Test
    func cacheRefreshesAfterThePreferredLanguageChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var language = "zh-Hans"
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { fixture.now },
            languageIdentifier: { language },
            collector: { enabled in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await store.collect(extensionEnabled: false, force: true)
        language = "en"

        #expect(!store.hasFreshCache)
        _ = await store.collect(extensionEnabled: false, force: false)
        #expect(collections == 2)
    }

    private static func items(extensionEnabled: Bool) -> [DiagnosticItem] {
        [
            DiagnosticItem(
                id: "extension",
                title: "Finder 扩展",
                passed: extensionEnabled,
                detail: extensionEnabled ? "已启用" : "未启用"
            ),
            DiagnosticItem(
                id: "codex",
                title: "Codex CLI",
                passed: true,
                detail: "/usr/local/bin/codex"
            )
        ]
    }
}

private struct Fixture {
    let suiteName: String
    let defaults: UserDefaults
    let settings: AppSettings
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        suiteName = "DiagnosticsStoreTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
