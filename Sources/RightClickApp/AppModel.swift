import AppKit
import FinderSync
import RightClickCore
import os

@MainActor
final class AppModel: ObservableObject {
    @Published var terminalProfile: TerminalProfile {
        didSet {
            settings.terminalProfile = terminalProfile
            var updated = menuConfiguration
            updated.terminalProfileID = terminalProfile.rawValue
            menuConfiguration = updated
        }
    }
    @Published var terminalWindowBehavior: TerminalWindowBehavior {
        didSet { settings.terminalWindowBehavior = terminalWindowBehavior }
    }
    @Published var menuConfiguration: MenuConfiguration {
        didSet { persistMenuConfiguration() }
    }
    @Published var lastStatus = "等待 Finder 操作"
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
    private let menuConfigurationURL: URL
    private let customTemplatesDirectory: URL
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
        self.menuConfigurationURL = menuConfigurationURL
        self.customTemplatesDirectory = customTemplatesDirectory
        terminalProfile = settings.terminalProfile
        terminalWindowBehavior = settings.terminalWindowBehavior
        var initialMenuConfiguration = MenuConfigurationFile.load(
            from: menuConfigurationURL
        )
        initialMenuConfiguration.terminalProfileID = settings.terminalProfile.rawValue
        menuConfiguration = initialMenuConfiguration
        diagnostics = diagnosticsStore.cached(extensionEnabled: false) ?? []
        diagnosticsAreAuthoritative = diagnosticsStore.hasFreshCache

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
            terminalProfile: terminalProfile,
            terminalWindowBehavior: terminalWindowBehavior
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

    func menuActionIsEnabled(_ action: RightClickAction) -> Bool {
        !menuConfiguration.disabledActions.contains(action.configurationID)
    }

    func setMenuAction(_ action: RightClickAction, isEnabled: Bool) {
        var updated = menuConfiguration
        if isEnabled {
            updated.disabledActions.remove(action.configurationID)
        } else {
            updated.disabledActions.insert(action.configurationID)
        }
        menuConfiguration = updated
    }

    func moveMenuAction(_ action: RightClickAction, by offset: Int) {
        var actions = configuredMenuActions
        guard let source = actions.firstIndex(of: action) else { return }
        let destination = source + offset
        guard actions.indices.contains(destination) else { return }
        actions.swapAt(source, destination)
        var updated = menuConfiguration
        updated.actionOrder = actions.map(\.configurationID)
        menuConfiguration = updated
    }

    func addCLIProfile() {
        let usedSlots = Set(menuConfiguration.cliProfiles.map(\.menuSlot))
        guard let slot = CLIProfile.validMenuSlots.first(where: {
            !usedSlots.contains($0)
        }) else {
            recordFailure("自定义 CLI 数量已达到上限。")
            return
        }
        var updated = menuConfiguration
        updated.cliProfiles.append(
            CLIProfile(
                id: UUID().uuidString.lowercased(),
                title: "自定义 CLI",
                executable: "command",
                menuSlot: slot
            )
        )
        menuConfiguration = updated
    }

    func removeCLIProfile(id: String) {
        var updated = menuConfiguration
        updated.cliProfiles.removeAll { $0.id == id }
        updated.actionOrder.removeAll { $0 == "cli:\(id)" }
        menuConfiguration = updated
    }

    func openCustomTemplatesDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: customTemplatesDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            NSWorkspace.shared.open(customTemplatesDirectory)
        } catch {
            recordFailure("无法打开自定义模板目录：\(error.localizedDescription)")
        }
    }

    func refreshCustomTemplates() {
        do {
            let templates = try TemplateMirror().synchronize(
                existing: menuConfiguration.customTemplates,
                sourceDirectory: customTemplatesDirectory,
                mirrorDirectory: MenuConfigurationFile.mirroredTemplatesDirectory(
                    configurationURL: menuConfigurationURL
                )
            )
            var updated = menuConfiguration
            updated.customTemplates = templates
            menuConfiguration = updated
            lastStatus = "已同步 \(templates.count) 个自定义模板"
        } catch {
            recordFailure("无法同步自定义模板：\(error.localizedDescription)")
        }
    }

    private func persistMenuConfiguration() {
        do {
            try MenuConfigurationFile.saveForHost(
                menuConfiguration,
                to: menuConfigurationURL
            )
            lastStatus = "Finder 菜单设置已保存"
        } catch {
            recordFailure("无法保存 Finder 菜单设置：\(error.localizedDescription)")
        }
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
            } catch {
                let message = error.localizedDescription
                recordFailure(message)
            }
        }
    }
}
