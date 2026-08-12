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
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await collect(store, extensionEnabled: false, force: true)
        let cached = await collect(store, extensionEnabled: true, force: false)

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
            collector: { enabled, _, _ in
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
        _ = await collect(store, extensionEnabled: false, force: true)
        currentDate.addTimeInterval(DiagnosticsStore.cacheLifetime + 1)
        detail = "second"

        #expect(cached(store, extensionEnabled: false)?[1].detail == "first")
        let refreshed = await collect(store, extensionEnabled: false, force: false)
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
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await collect(store, extensionEnabled: false, force: true)
        currentDate.addTimeInterval(-1)

        #expect(!hasFreshCache(store))
        _ = await collect(store, extensionEnabled: false, force: false)
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
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        #expect(cached(store, extensionEnabled: false) == nil)
        #expect(!hasFreshCache(store))
        _ = await collect(store, extensionEnabled: false, force: false)
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
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await collect(store, extensionEnabled: false, force: true)
        language = "en"

        #expect(!hasFreshCache(store))
        _ = await collect(store, extensionEnabled: false, force: false)
        #expect(collections == 2)
    }

    @Test
    func terminalProfileChangeInvalidatesTheCache() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { fixture.now },
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )

        _ = await collect(store, extensionEnabled: false, force: true)
        #expect(!store.hasFreshCache(
            terminalProfile: .ghostty,
            menuConfiguration: Self.menuConfiguration
        ))
        _ = await store.collect(
            extensionEnabled: false,
            force: false,
            terminalProfile: .ghostty,
            menuConfiguration: Self.menuConfiguration
        )
        #expect(collections == 2)
    }

    @Test
    func menuConfigurationChangeInvalidatesTheCache() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var collections = 0
        let store = DiagnosticsStore(
            settings: fixture.settings,
            now: { fixture.now },
            collector: { enabled, _, _ in
                collections += 1
                return Self.items(extensionEnabled: enabled)
            }
        )
        var changed = Self.menuConfiguration
        changed.disabledActions.insert(RightClickAction.openInZed.configurationID)

        _ = await collect(store, extensionEnabled: false, force: true)
        #expect(!store.hasFreshCache(
            terminalProfile: Self.terminalProfile,
            menuConfiguration: changed
        ))
        _ = await store.collect(
            extensionEnabled: false,
            force: false,
            terminalProfile: Self.terminalProfile,
            menuConfiguration: changed
        )
        #expect(collections == 2)
    }

    private static let terminalProfile = TerminalProfile.terminal
    private static let menuConfiguration = MenuConfiguration(
        terminalProfileID: TerminalProfile.terminal.rawValue
    )

    private func collect(
        _ store: DiagnosticsStore,
        extensionEnabled: Bool,
        force: Bool
    ) async -> [DiagnosticItem]? {
        await store.collect(
            extensionEnabled: extensionEnabled,
            force: force,
            terminalProfile: Self.terminalProfile,
            menuConfiguration: Self.menuConfiguration
        )
    }

    private func cached(
        _ store: DiagnosticsStore,
        extensionEnabled: Bool
    ) -> [DiagnosticItem]? {
        store.cached(
            extensionEnabled: extensionEnabled,
            terminalProfile: Self.terminalProfile,
            menuConfiguration: Self.menuConfiguration
        )
    }

    private func hasFreshCache(_ store: DiagnosticsStore) -> Bool {
        store.hasFreshCache(
            terminalProfile: Self.terminalProfile,
            menuConfiguration: Self.menuConfiguration
        )
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
