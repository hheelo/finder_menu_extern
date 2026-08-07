import RightClickCore

/// 诊断刷新策略与结果规范化。UI 状态仍由 AppModel 发布。
@MainActor
final class DiagnosticsStore {
    private var lastRefresh: ContinuousClock.Instant?
    private var isCollecting = false

    func collect(
        extensionEnabled: Bool,
        force: Bool
    ) async -> [DiagnosticItem]? {
        guard !isCollecting else { return nil }
        if !force, let lastRefresh,
           ContinuousClock().now - lastRefresh < .seconds(30) {
            return nil
        }

        lastRefresh = ContinuousClock().now
        isCollecting = true
        defer { isCollecting = false }

        return await AppDiagnostics.collect(
            extensionEnabled: extensionEnabled
        )
    }
}
