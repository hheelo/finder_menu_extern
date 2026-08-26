import AppKit
import FinderSync
import RightClickAppLogic
import RightClickCore
import SwiftUI
import os

@MainActor
final class AppModel: ObservableObject {
    private static let maximumErrorHistoryCount = 10

    @Published var terminalProfile: TerminalProfile {
        didSet {
            settings.terminalProfile = terminalProfile
            menuConfigurationStore.updateImmediately {
                $0.terminalProfileID = terminalProfile.rawValue
            }
            Task { await refreshDiagnostics() }
        }
    }
    @Published var terminalWindowBehavior: TerminalWindowBehavior {
        didSet { settings.terminalWindowBehavior = terminalWindowBehavior }
    }
    @Published var menuBarIconEnabled: Bool {
        didSet {
            settings.menuBarIconEnabled = menuBarIconEnabled
            onMenuBarIconEnabledChange?(menuBarIconEnabled)
        }
    }
    @Published var hasCompletedOnboarding: Bool
    @Published var shouldPresentOnboarding = false
    @Published var menuConfiguration: MenuConfiguration {
        didSet {
            menuConfigurationStore.replace(with: menuConfiguration)
            configuredMenuActions = Self.orderedActions(
                for: menuConfiguration
            )
        }
    }
    @Published private(set) var configuredMenuActions: [RightClickAction] = []
    @Published var lastStatus = L10n.text(
        "status.waiting",
        fallback: "等待 Finder 操作"
    )
    @Published var errorHistory: [AppErrorRecord] = []
    @Published private(set) var extensionEnabled = false
    @Published private(set) var extensionDetectionUnavailable = false
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    var configurationRecoveryRequired: Bool {
        menuConfigurationStore.requiresConfigurationRecovery
    }

    let settings: AppSettings
    private let deepLinkCoordinator: DeepLinkCoordinator
    private let diagnosticsStore: DiagnosticsStore
    private let finderSessionManager: FinderSessionManager
    private let extensionStatusProvider: @MainActor () async -> Bool?
    private let notifier: any UserNotifying
    let menuConfigurationStore: MenuConfigurationStore
    let actionLogStore: LocalActionLogStore
    let actionLogSessionTracker: LocalActionSessionTracker
    let extensionActionLogURL: URL?
    private var diagnosticsAreAuthoritative = false
    private var isRefreshingExtensionStatus = false
    var onMenuBarIconEnabledChange: ((Bool) -> Void)?

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
        menuConfigurationURL: URL = MenuConfigurationFile.hostURL(),
        customTemplatesDirectory: URL = MenuConfigurationFile.hostTemplatesDirectory(),
        actionLogStore: LocalActionLogStore? = nil,
        extensionActionLogURL: URL? = nil,
        extensionStatusProvider: (@MainActor () async -> Bool?)? = nil,
        performInitialRefresh: Bool = true
    ) {
        self.settings = settings
        let resolvedActionLogStore = actionLogStore ?? LocalActionLogStore(
            fileURL: AppEnvironment.isRunningTests
                ? nil
                : LocalActionLogFile.hostURL()
        )
        self.actionLogStore = resolvedActionLogStore
        actionLogSessionTracker = LocalActionSessionTracker(
            store: resolvedActionLogStore,
            markerURL: resolvedActionLogStore.fileURL.map {
                LocalActionLogFile.sessionMarkerURL(for: $0)
            }
        )
        self.extensionActionLogURL = extensionActionLogURL ?? (
            AppEnvironment.isRunningTests
                ? nil
                : LocalActionLogFile.extensionHostURL()
        )
        deepLinkCoordinator = DeepLinkCoordinator(
            extensionRequestToken: extensionRequestToken,
            executor: executor,
            menuConfiguration: {
                MenuConfigurationFile.load(from: menuConfigurationURL)
            },
            customTemplatesDirectory: { customTemplatesDirectory },
            recordAction: { action, result, category in
                resolvedActionLogStore.append(LocalActionRecord(
                    source: .host,
                    action: action,
                    result: result,
                    errorCategory: category
                ))
            },
            applicationURL: applicationURL
        )
        diagnosticsStore = DiagnosticsStore(settings: settings)
        let resolvedFinderSessionManager = FinderSessionManager(
            settings: settings
        )
        finderSessionManager = resolvedFinderSessionManager
        self.extensionStatusProvider = extensionStatusProvider ?? {
            await resolvedFinderSessionManager.extensionIsEnabled()
        }
        self.notifier = notifier
        terminalProfile = settings.terminalProfile
        terminalWindowBehavior = settings.terminalWindowBehavior
        menuBarIconEnabled = settings.menuBarIconEnabled
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        let configurationStore = MenuConfigurationStore(
            configurationURL: menuConfigurationURL,
            customTemplatesDirectory: customTemplatesDirectory,
            terminalProfileID: settings.terminalProfile.rawValue
        )
        menuConfigurationStore = configurationStore
        menuConfiguration = configurationStore.configuration
        configuredMenuActions = Self.orderedActions(for: menuConfiguration)
        diagnostics = diagnosticsStore.cached(
            extensionEnabled: false,
            terminalProfile: terminalProfile,
            menuConfiguration: menuConfiguration
        ) ?? []
        diagnosticsAreAuthoritative = diagnosticsStore.hasFreshCache(
            terminalProfile: terminalProfile,
            menuConfiguration: menuConfiguration
        )

        configurationStore.onChange = { [weak self] configuration in
            self?.menuConfiguration = configuration
        }
        configurationStore.onStatus = { [weak self] status in
            self?.lastStatus = status
        }
        configurationStore.onFailure = { [weak self] message in
            self?.recordFailure(message)
        }
        configurationStore.deliverDeferredInitializationFailure()

        if performInitialRefresh {
            Task { await refreshForUserPresentation() }
        }
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func refreshExtensionStatus() async {
        // 首次向导会频繁轮询；旧系统的一次 pluginkit 检测可持续 5 秒。
        // 同一时刻只允许一项检测，避免多个进程重叠并乱序覆盖状态。
        guard !isRefreshingExtensionStatus else { return }
        isRefreshingExtensionStatus = true
        defer { isRefreshingExtensionStatus = false }
        applyExtensionStatus(await extensionStatusProvider())
    }

    func applyExtensionStatus(_ enabled: Bool?) {
        guard let enabled else {
            extensionDetectionUnavailable = true
            if !diagnostics.isEmpty {
                diagnostics = normalizeExtensionStatus(in: diagnostics)
            }
            return
        }
        extensionDetectionUnavailable = false
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
            terminalWindowBehavior: terminalWindowBehavior,
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
        let requestedTerminalProfile = terminalProfile
        let requestedMenuConfiguration = menuConfiguration
        if let collected = await diagnosticsStore.collect(
            extensionEnabled: extensionEnabled,
            force: force,
            terminalProfile: requestedTerminalProfile,
            menuConfiguration: requestedMenuConfiguration
        ) {
            isRefreshingDiagnostics = false
            // 用户可能在登录 shell 探测期间改了终端或编辑器开关。旧收集结果
            // 不能覆盖新上下文；立即按最新配置再收一次。
            guard requestedTerminalProfile == terminalProfile,
                  requestedMenuConfiguration == menuConfiguration else {
                await refreshDiagnostics(force: true)
                return
            }
            // 旧系统的 pluginkit 检测可能在 collect 的 await 期间返回。以完成时
            // 的最新状态改写这一行，避免一直显示初始化时的 false。
            diagnostics = normalizeExtensionStatus(in: collected)
            diagnosticsAreAuthoritative = true
        } else {
            isRefreshingDiagnostics = false
        }
    }

    func copyDiagnostics() {
        let report = AppDiagnostics.report(
            diagnostics,
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        lastStatus = L10n.text(
            "status.copied_diagnostics",
            fallback: "诊断信息已复制"
        )
    }

    private func apply(_ event: DeepLinkEvent) {
        switch event {
        case let .status(status):
            lastStatus = status
        case let .trustedFailure(message):
            reportTrustedFailure(message)
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
                passed: !extensionDetectionUnavailable && extensionEnabled,
                detail: extensionDiagnosticDetail
            )
        }
    }

    var extensionDiagnosticDetail: String {
        if extensionDetectionUnavailable {
            return L10n.text(
                "diagnostic.unable_to_detect",
                fallback: "无法检测"
            )
        }
        return extensionEnabled
            ? L10n.text("diagnostic.enabled", fallback: "已启用")
            : L10n.text("diagnostic.not_enabled", fallback: "未启用")
    }

    func recordFailure(_ message: String) {
        let record = AppErrorRecord(message: message)
        // 界面每次呈现都会重试模板同步。同一条持续性错误只保留最新时间戳，
        // 避免它挤掉最近十条历史里真正不同的失败。
        errorHistory.removeAll { $0.message == message }
        errorHistory.insert(record, at: 0)
        if errorHistory.count > Self.maximumErrorHistoryCount {
            errorHistory.removeLast(
                errorHistory.count - Self.maximumErrorHistoryCount
            )
        }
    }

    private func refreshFinderSessionIfNeeded() {
        guard finderSessionManager.consumeRequiredRefresh() else { return }
        restartFinder(successStatus: L10n.text(
            "status.reloaded_finder",
            fallback: "已为当前版本重新加载 Finder"
        ))
    }

    func restartFinder(successStatus: String) {
        lastStatus = L10n.text(
            "status.restarting_finder",
            fallback: "正在重启 Finder"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await finderSessionManager.restartFinder()
                lastStatus = successStatus
            } catch {
                let message = error.localizedDescription
                recordFailure(message)
            }
        }
    }
}
