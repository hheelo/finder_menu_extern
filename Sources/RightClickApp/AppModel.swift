import AppKit
import FinderSync
import RightClickCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet { settings.terminalProfile = terminalProfile }
    }
    @Published var lastStatus = "等待 Finder 操作"
    @Published var lastError: String?
    @Published private(set) var errorHistory: [AppErrorRecord] = []
    @Published private(set) var needsFinderRestartHint = false
    @Published private(set) var extensionEnabled = false
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    private let settings: AppSettings
    private let deepLinkCoordinator: DeepLinkCoordinator
    private let diagnosticsStore: DiagnosticsStore
    private let finderSessionManager: FinderSessionManager
    private let notifier: any UserNotifying
    private var diagnosticsAreAuthoritative = false

    init(
        settings: AppSettings = .shared,
        executor: any CLIExecuting = ActionExecutor(),
        extensionRequestToken: @escaping @MainActor () -> String? = {
            ExtensionRequestTokenStore.loadForHost()
        },
        notifier: any UserNotifying = SystemUserNotifier(),
        applicationURL: @escaping @MainActor (ExternalApplication) -> URL? = {
            application in
            let workspace = NSWorkspace.shared
            return application.url(
                bundleIdentifierLookup: {
                    workspace.urlForApplication(withBundleIdentifier: $0)
                }
            )
        },
        performInitialRefresh: Bool = true
    ) {
        self.settings = settings
        deepLinkCoordinator = DeepLinkCoordinator(
            extensionRequestToken: extensionRequestToken,
            executor: executor,
            applicationURL: applicationURL
        )
        diagnosticsStore = DiagnosticsStore(settings: settings)
        finderSessionManager = FinderSessionManager(settings: settings)
        self.notifier = notifier
        terminalProfile = settings.terminalProfile
        diagnostics = diagnosticsStore.cached(extensionEnabled: false) ?? []
        diagnosticsAreAuthoritative = diagnosticsStore.hasFreshCache

        if performInitialRefresh {
            refreshExtensionStatus()
            Task { await refreshDiagnostics() }
        }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func refreshExtensionStatus() {
        Task { [weak self] in
            guard let self else { return }
            applyExtensionStatus(
                await finderSessionManager.extensionIsEnabled()
            )
        }
    }

    private func applyExtensionStatus(_ enabled: Bool) {
        extensionEnabled = enabled
        if !diagnostics.isEmpty {
            diagnostics = normalizeExtensionStatus(in: diagnostics)
        }
        if enabled {
            refreshFinderSessionIfNeeded()
        }
    }

    func handle(url: URL) {
        deepLinkCoordinator.dispatch(
            url,
            terminalProfile: terminalProfile,
            commandAvailability: { [weak self] command in
                guard self?.diagnosticsAreAuthoritative == true else {
                    return nil
                }
                return self?.diagnostics.first {
                    $0.id == command.rawValue
                }?.passed
            }
        ) { [weak self] event in
            self?.apply(event)
        }
    }

    func refreshDiagnostics(force: Bool = false) async {
        guard !isRefreshingDiagnostics else { return }
        isRefreshingDiagnostics = true
        defer { isRefreshingDiagnostics = false }
        if let collected = await diagnosticsStore.collect(
            extensionEnabled: extensionEnabled,
            force: force
        ) {
            // 旧系统的 pluginkit 检测可能在 collect 的 await 期间返回。以完成时
            // 的最新状态改写这一行，避免一直显示初始化时的 false。
            diagnostics = normalizeExtensionStatus(in: collected)
            diagnosticsAreAuthoritative = true
        }
    }

    func copyDiagnostics() {
        let report = AppDiagnostics.report(
            diagnostics,
            terminalProfile: terminalProfile
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        lastStatus = "诊断信息已复制"
        lastError = nil
    }

    func clearErrors() {
        errorHistory.removeAll()
        lastError = nil
    }

    func restartFinder() {
        restartFinder(successStatus: "Finder 已重新启动")
    }

    private func apply(_ event: DeepLinkEvent) {
        switch event {
        case let .status(status):
            lastStatus = status
        case let .trustedFailure(message):
            reportTrustedFailure(message)
        case .legacyRequest:
            needsFinderRestartHint = true
        }
    }

    private func reportTrustedFailure(_ message: String) {
        recordFailure(message)
        notifier.report(message)
    }

    private func normalizeExtensionStatus(
        in items: [DiagnosticItem]
    ) -> [DiagnosticItem] {
        items.map { item in
            guard item.id == "extension" else { return item }
            return DiagnosticItem(
                id: item.id,
                title: item.title,
                passed: extensionEnabled,
                detail: extensionEnabled ? "已启用" : "未启用"
            )
        }
    }

    private func recordFailure(_ message: String) {
        let record = AppErrorRecord(message: message)
        errorHistory.insert(record, at: 0)
        if errorHistory.count > 10 {
            errorHistory.removeLast(errorHistory.count - 10)
        }
        lastError = message
    }

    private func refreshFinderSessionIfNeeded() {
        guard finderSessionManager.consumeRequiredRefresh() else { return }
        restartFinder(successStatus: "已为当前版本重新加载 Finder")
    }

    private func restartFinder(successStatus: String) {
        lastStatus = "正在重启 Finder"
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await finderSessionManager.restartFinder()
                lastStatus = successStatus
                needsFinderRestartHint = false
            } catch {
                let message = error.localizedDescription
                recordFailure(message)
            }
        }
    }
}
