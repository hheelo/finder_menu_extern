import Foundation
import RightClickCore

/// 诊断刷新策略与结果规范化。UI 状态仍由 AppModel 发布。
@MainActor
final class DiagnosticsStore {
    static let cacheLifetime: TimeInterval = 24 * 60 * 60

    private struct Snapshot: Codable {
        let capturedAt: Date
        let languageIdentifier: String
        let items: [DiagnosticItem]
    }

    private let settings: AppSettings
    private let now: () -> Date
    private let languageIdentifier: () -> String
    private let collector: (Bool) async -> [DiagnosticItem]
    private var isCollecting = false

    init(
        settings: AppSettings = .shared,
        now: @escaping () -> Date = Date.init,
        languageIdentifier: @escaping () -> String = {
            L10n.currentLanguageIdentifier
        },
        collector: @escaping (Bool) async -> [DiagnosticItem] = {
            await AppDiagnostics.collect(extensionEnabled: $0)
        }
    ) {
        self.settings = settings
        self.now = now
        self.languageIdentifier = languageIdentifier
        self.collector = collector
    }

    /// 冷启动先展示上次结果；Finder 扩展状态变化频繁，永远使用本次实况。
    func cached(extensionEnabled: Bool) -> [DiagnosticItem]? {
        guard let snapshot = loadSnapshot() else { return nil }
        return withExtensionState(
            snapshot.items,
            enabled: extensionEnabled
        )
    }

    var hasFreshCache: Bool {
        guard let snapshot = loadSnapshot() else { return false }
        return isFresh(snapshot)
    }

    func collect(
        extensionEnabled: Bool,
        force: Bool
    ) async -> [DiagnosticItem]? {
        guard !isCollecting else { return nil }
        if !force, let snapshot = loadSnapshot(), isFresh(snapshot) {
            return withExtensionState(
                snapshot.items,
                enabled: extensionEnabled
            )
        }

        isCollecting = true
        defer { isCollecting = false }

        let collected = await collector(extensionEnabled)
        let cacheable = collected.filter { $0.id != "extension" }
        if let data = try? JSONEncoder().encode(
            Snapshot(
                capturedAt: now(),
                languageIdentifier: languageIdentifier(),
                items: cacheable
            )
        ) {
            settings.cachedDiagnostics = data
        }
        return withExtensionState(
            cacheable,
            enabled: extensionEnabled
        )
    }

    private func loadSnapshot() -> Snapshot? {
        guard let data = settings.cachedDiagnostics,
              let snapshot = try? JSONDecoder().decode(
                  Snapshot.self,
                  from: data
              ) else {
            return nil
        }
        return snapshot
    }

    private func isFresh(_ snapshot: Snapshot) -> Bool {
        let age = now().timeIntervalSince(snapshot.capturedAt)
        return age >= 0
            && age < Self.cacheLifetime
            && snapshot.languageIdentifier == languageIdentifier()
    }

    private func withExtensionState(
        _ items: [DiagnosticItem],
        enabled: Bool
    ) -> [DiagnosticItem] {
        [
            DiagnosticItem(
                id: "extension",
                title: L10n.text("diagnostic.extension", fallback: "Finder 扩展"),
                passed: enabled,
                detail: enabled
                    ? L10n.text("diagnostic.enabled", fallback: "已启用")
                    : L10n.text("diagnostic.not_enabled", fallback: "未启用")
            )
        ] + items.filter { $0.id != "extension" }
    }
}
