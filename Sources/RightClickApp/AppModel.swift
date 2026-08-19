import AppKit
import FinderSync
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers
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
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var shouldPresentOnboarding = false
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
    @Published private(set) var errorHistory: [AppErrorRecord] = []
    @Published private(set) var extensionEnabled = false
    @Published private(set) var extensionDetectionUnavailable = false
    @Published private(set) var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRefreshingDiagnostics = false

    private let settings: AppSettings
    private let deepLinkCoordinator: DeepLinkCoordinator
    private let diagnosticsStore: DiagnosticsStore
    private let finderSessionManager: FinderSessionManager
    private let notifier: any UserNotifying
    private let menuConfigurationStore: MenuConfigurationStore
    private let actionLogStore: LocalActionLogStore
    private let actionLogSessionTracker: LocalActionSessionTracker
    private let extensionActionLogURL: URL?
    private var diagnosticsAreAuthoritative = false
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
        finderSessionManager = FinderSessionManager(settings: settings)
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

    func refreshExtensionStatus() {
        Task { [weak self] in
            guard let self else { return }
            applyExtensionStatus(
                await finderSessionManager.extensionIsEnabled()
            )
        }
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

    func beginLocalActionLogSession() {
        actionLogSessionTracker.begin()
    }

    func endLocalActionLogSession() {
        actionLogSessionTracker.end()
    }

    func exportLocalActionLog() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "RightClick-Local-Action-Log.txt"
        panel.title = L10n.text(
            "settings.export_local_log",
            fallback: "导出本地动作日志"
        )
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        let extensionRecords = extensionActionLogURL.map {
            LocalActionLogStore.load(from: $0)
        } ?? []
        let report = LocalActionLogReport.make(
            hostRecords: actionLogStore.records(),
            extensionRecords: extensionRecords,
            appVersion: AppVersion.displayString ?? "unknown"
        )
        do {
            try Data(report.utf8).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            lastStatus = L10n.text(
                "status.exported_local_log",
                fallback: "本地动作日志已导出"
            )
        } catch {
            recordFailure(L10n.format(
                "error.export_local_log",
                fallback: "无法导出本地动作日志：%@",
                error.localizedDescription
            ))
        }
    }

    func clearErrors() {
        errorHistory.removeAll()
    }

    private static func orderedActions(
        for configuration: MenuConfiguration
    ) -> [RightClickAction] {
        let rank = configuration.actionOrder.enumerated().reduce(
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

    func moveMenuActions(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        var actions = configuredMenuActions
        actions.move(fromOffsets: source, toOffset: destination)
        menuConfigurationStore.updateImmediately {
            $0.actionOrder = actions.map(\.configurationID)
        }
    }

    func restoreDefaultMenuActionOrder() {
        menuConfigurationStore.updateImmediately {
            $0.actionOrder = []
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

    func removeCLIArgument(profileID: String, at index: Int) {
        menuConfigurationStore.updateImmediately { updated in
            guard let profileIndex = updated.cliProfiles.firstIndex(
                where: { $0.id == profileID }
            ), updated.cliProfiles[profileIndex].arguments.indices.contains(index)
            else { return }
            updated.cliProfiles[profileIndex].arguments.remove(at: index)
        }
    }

    func templateFilename(for template: FileTemplate) -> String {
        menuConfiguration.templateOverrides[template.rawValue]?.filename ?? ""
    }

    func setTemplateFilename(_ filename: String, for template: FileTemplate) {
        var updated = menuConfiguration
        var templateOverride = updated.templateOverrides[template.rawValue]
            ?? TemplateOverride()
        templateOverride.filename = filename.isEmpty ? nil : filename
        if templateOverride.filename == nil,
           templateOverride.encoding == nil {
            updated.templateOverrides.removeValue(forKey: template.rawValue)
        } else {
            updated.templateOverrides[template.rawValue] = templateOverride
        }
        menuConfiguration = updated
    }

    func templateEncoding(for template: FileTemplate) -> TemplateEncoding {
        menuConfiguration.templateOverrides[template.rawValue]?
            .resolvedEncoding ?? .utf8
    }

    func setTemplateEncoding(
        _ encoding: TemplateEncoding,
        for template: FileTemplate
    ) {
        menuConfigurationStore.updateImmediately { updated in
            var templateOverride = updated.templateOverrides[template.rawValue]
                ?? TemplateOverride()
            // UTF-8 是内置默认，不保存冗余覆盖。
            templateOverride.encoding = encoding == .utf8
                ? nil
                : encoding.rawValue
            if templateOverride.filename == nil,
               templateOverride.encoding == nil {
                updated.templateOverrides.removeValue(forKey: template.rawValue)
            } else {
                updated.templateOverrides[template.rawValue] = templateOverride
            }
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

    func refreshCustomTemplates() async {
        await menuConfigurationStore.refreshCustomTemplates()
    }

    /// 用户明确打开或恢复界面时的唯一刷新入口。
    ///
    /// Finder 深链也会冷启动宿主，但那条路径绝不能展示 onboarding、窗口或更新
    /// 界面。所有用户呈现入口先由 `AppPresentation` 判定，再调用本方法，避免新增
    /// 一项刷新职责时再次漏掉某个窗口恢复分支。
    func refreshForUserPresentation() async {
        if !hasCompletedOnboarding && !AppEnvironment.isRunningUITests {
            shouldPresentOnboarding = true
        }
        guard !AppEnvironment.isRunningTests else { return }
        refreshExtensionStatus()
        await refreshCustomTemplates()
        await refreshDiagnostics()
    }

    func addMonitoredDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text(
            "button.add_monitored_directory",
            fallback: "添加目录"
        )
        guard panel.runModal() == .OK else { return }

        let selectedPaths = panel.urls.map { $0.standardizedFileURL.path }
        menuConfigurationStore.updateImmediately { updated in
            updated.monitoredDirectories = MonitoredDirectoryPolicy
                .sanitizedPaths(updated.monitoredDirectories + selectedPaths)
        }
    }

    func removeMonitoredDirectory(_ path: String) {
        menuConfigurationStore.updateImmediately {
            $0.monitoredDirectories.removeAll { $0 == path }
        }
    }

    func monitorAllDirectories() {
        menuConfigurationStore.updateImmediately {
            $0.monitoredDirectories = []
        }
    }

    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        settings.hasCompletedOnboarding = true
        hasCompletedOnboarding = true
        shouldPresentOnboarding = false
    }

    func skipOnboarding() {
        completeOnboarding()
    }

    func restartOnboarding() {
        settings.hasCompletedOnboarding = false
        hasCompletedOnboarding = false
        shouldPresentOnboarding = true
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

    private func recordFailure(_ message: String) {
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

    private func restartFinder(successStatus: String) {
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
