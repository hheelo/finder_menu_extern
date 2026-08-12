import AppKit
import FinderSync
import RightClickCore
import os

@MainActor
final class AppModel: ObservableObject {
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
    @Published var menuConfiguration: MenuConfiguration {
        didSet { menuConfigurationStore.replace(with: menuConfiguration) }
    }
    @Published var lastStatus = L10n.text(
        "status.waiting",
        fallback: "等待 Finder 操作"
    )
    @Published var lastError: String?
    @Published private(set) var errorHistory: [AppErrorRecord] = []
    @Published private(set) var extensionEnabled = false
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    private let settings: AppSettings
    private let deepLinkCoordinator: DeepLinkCoordinator
    private let diagnosticsStore: DiagnosticsStore
    private let finderSessionManager: FinderSessionManager
    private let notifier: any UserNotifying
    private let menuConfigurationStore: MenuConfigurationStore
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
        menuConfigurationURL: URL = MenuConfigurationFile.hostURL(),
        customTemplatesDirectory: URL = MenuConfigurationFile.hostTemplatesDirectory(),
        performInitialRefresh: Bool = true
    ) {
        self.settings = settings
        deepLinkCoordinator = DeepLinkCoordinator(
            extensionRequestToken: extensionRequestToken,
            executor: executor,
            menuConfiguration: {
                MenuConfigurationFile.load(from: menuConfigurationURL)
            },
            applicationURL: applicationURL
        )
        diagnosticsStore = DiagnosticsStore(settings: settings)
        finderSessionManager = FinderSessionManager(settings: settings)
        self.notifier = notifier
        terminalProfile = settings.terminalProfile
        terminalWindowBehavior = settings.terminalWindowBehavior
        let configurationStore = MenuConfigurationStore(
            configurationURL: menuConfigurationURL,
            customTemplatesDirectory: customTemplatesDirectory,
            terminalProfileID: settings.terminalProfile.rawValue
        )
        menuConfigurationStore = configurationStore
        menuConfiguration = configurationStore.configuration
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
            refreshCustomTemplates()
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
        lastError = nil
    }

    func clearErrors() {
        errorHistory.removeAll()
        lastError = nil
    }

    var configuredMenuActions: [RightClickAction] {
        let rank = menuConfiguration.actionOrder.enumerated().reduce(
            into: [String: Int]()
        ) {
            $0[$1.element, default: $1.offset] = min(
                $0[$1.element] ?? $1.offset,
                $1.offset
            )
        }
        return RightClickAction.allMenuActions.enumerated().sorted { lhs, rhs in
            let left = rank[lhs.element.configurationID] ?? Int.max
            let right = rank[rhs.element.configurationID] ?? Int.max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    /// 复制发生在扩展进程里，所以这个设置的真相是菜单配置文件而不是
    /// UserDefaults——写回配置 Store 即下发到扩展容器。
    var clipboardSeparator: ClipboardSeparator {
        get { menuConfiguration.clipboardSeparator }
        set {
            menuConfigurationStore.updateImmediately {
                $0.copySeparator = newValue.rawValue
            }
        }
    }

    func menuActionIsEnabled(_ action: RightClickAction) -> Bool {
        !menuConfiguration.disabledActions.contains(action.configurationID)
    }

    func setMenuAction(_ action: RightClickAction, isEnabled: Bool) {
        menuConfigurationStore.updateImmediately { updated in
            if isEnabled {
                updated.disabledActions.remove(action.configurationID)
            } else {
                updated.disabledActions.insert(action.configurationID)
            }
        }
        if ExternalApplication.forOpenAction(action) != nil {
            Task { await refreshDiagnostics() }
        }
    }

    func moveMenuAction(_ action: RightClickAction, by offset: Int) {
        var actions = configuredMenuActions
        guard let source = actions.firstIndex(of: action) else { return }
        let destination = source + offset
        guard actions.indices.contains(destination) else { return }
        actions.swapAt(source, destination)
        menuConfigurationStore.updateImmediately {
            $0.actionOrder = actions.map(\.configurationID)
        }
    }

    func addCLIProfile() {
        let usedSlots = Set(menuConfiguration.cliProfiles.map(\.menuSlot))
        guard let slot = CLIProfile.validMenuSlots.first(where: {
            !usedSlots.contains($0)
        }) else {
            recordFailure(L10n.text(
                "error.cli_limit",
                fallback: "自定义 CLI 数量已达到上限。"
            ))
            return
        }
        menuConfigurationStore.updateImmediately {
            $0.cliProfiles.append(CLIProfile(
                id: UUID().uuidString.lowercased(),
                title: L10n.text(
                    "settings.default_cli_title",
                    fallback: "自定义 CLI"
                ),
                executable: "command",
                menuSlot: slot
            ))
        }
    }

    func removeCLIProfile(id: String) {
        menuConfigurationStore.updateImmediately {
            $0.cliProfiles.removeAll { $0.id == id }
        }
    }

    func openCustomTemplatesDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: menuConfigurationStore.customTemplatesDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            NSWorkspace.shared.open(
                menuConfigurationStore.customTemplatesDirectory
            )
        } catch {
            recordFailure(L10n.format(
                "error.open_templates",
                fallback: "无法打开自定义模板目录：%@",
                error.localizedDescription
            ))
        }
    }

    func refreshCustomTemplates() {
        menuConfigurationStore.refreshCustomTemplates()
    }

    func persistMenuConfigurationImmediately() {
        menuConfigurationStore.persistImmediately()
    }

    func flushPendingMenuConfiguration() {
        menuConfigurationStore.flushPendingPersist()
    }

    func restartFinder() {
        restartFinder(successStatus: L10n.text(
            "status.restarted_finder",
            fallback: "Finder 已重新启动"
        ))
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
                passed: extensionEnabled,
                detail: extensionEnabled
                    ? L10n.text("diagnostic.enabled", fallback: "已启用")
                    : L10n.text("diagnostic.not_enabled", fallback: "未启用")
            )
        }
    }

    private func recordFailure(_ message: String) {
        let record = AppErrorRecord(message: message)
        // 界面每次呈现都会重试模板同步。同一条持续性错误只保留最新时间戳，
        // 避免它挤掉最近十条历史里真正不同的失败。
        errorHistory.removeAll { $0.message == message }
        errorHistory.insert(record, at: 0)
        if errorHistory.count > 10 {
            errorHistory.removeLast(errorHistory.count - 10)
        }
        lastError = message
    }

    private func refreshFinderSessionIfNeeded() {
        guard finderSessionManager.consumeRequiredRefresh() else { return }
        restartFinder(successStatus: L10n.text(
            "status.reloaded_finder",
            fallback: "已为当前版本重新加载 Finder"
        ))
    }

    private func restartFinder(successStatus: String) {
        lastStatus = L10n.text(
            "status.restarting_finder",
            fallback: "正在重启 Finder"
        )
        lastError = nil

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
