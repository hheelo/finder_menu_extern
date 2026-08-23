import Foundation
import RightClickCore

/// Finder 菜单配置的唯一宿主持有者。
///
/// 配置的加载、编辑、落盘和自定义模板同步都集中在这里；`AppModel` 只把
/// `onChange` 转发成 `@Published` 状态。这样新增配置项时不会再次把文件系统
/// 细节和界面状态混在一起。
@MainActor
final class MenuConfigurationStore {
    typealias Loader = (URL) -> MenuConfigurationLoadResult
    typealias Saver = (MenuConfiguration, URL) throws -> Void
    typealias InvalidConfigurationBackupper = (
        MenuConfigurationLoadResult,
        URL
    ) throws -> URL?
    typealias ExistingConfigurationBackupper = (URL) throws -> URL?
    typealias TemplateSynchronizer = @Sendable (
        _ existing: [CustomFileTemplate],
        _ sourceDirectory: URL,
        _ mirrorDirectory: URL
    ) throws -> TemplateMirrorResult

    private(set) var configuration: MenuConfiguration
    private(set) var recoveryFailure: MenuConfigurationLoadFailure?
    var onChange: ((MenuConfiguration) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    let customTemplatesDirectory: URL

    private let configurationURL: URL
    private let save: Saver
    private let backupInvalidConfiguration: InvalidConfigurationBackupper
    private let backupExistingConfiguration: ExistingConfigurationBackupper
    private let synchronizeTemplates: TemplateSynchronizer
    private let persistenceDelay: Duration
    private var pendingPersist: Task<Void, Never>?
    private var deferredInitializationFailure: String?
    private var isRefreshingCustomTemplates = false

    init(
        configurationURL: URL,
        customTemplatesDirectory: URL,
        terminalProfileID: String,
        load: Loader = { MenuConfigurationFile.loadResult(from: $0) },
        save: @escaping Saver = {
            try MenuConfigurationFile.saveForHost($0, to: $1)
        },
        backupInvalidConfiguration: @escaping InvalidConfigurationBackupper = {
            try MenuConfigurationBackup.preserveInvalidConfiguration(
                $0,
                sourceURL: $1
            )
        },
        backupExistingConfiguration: @escaping ExistingConfigurationBackupper = {
            try MenuConfigurationBackup.preserveExistingConfiguration(at: $0)
        },
        persistenceDelay: Duration = .milliseconds(400),
        synchronizeTemplates: @escaping TemplateSynchronizer = {
            try TemplateMirror().synchronize(
                existing: $0,
                sourceDirectory: $1,
                mirrorDirectory: $2
            )
        }
    ) {
        self.configurationURL = configurationURL
        self.customTemplatesDirectory = customTemplatesDirectory
        self.save = save
        self.backupInvalidConfiguration = backupInvalidConfiguration
        self.backupExistingConfiguration = backupExistingConfiguration
        self.persistenceDelay = persistenceDelay
        self.synchronizeTemplates = synchronizeTemplates

        let loadResult = load(configurationURL)
        let loaded = loadResult.configuration
        var initial = loaded
        initial.terminalProfileID = terminalProfileID
        configuration = initial
        recoveryFailure = loadResult.failure

        if recoveryFailure != nil {
            do {
                let backupURL = try backupInvalidConfiguration(
                    loadResult,
                    configurationURL
                )
                deferredInitializationFailure = Self.recoveryFailureMessage(
                    loadResult.failure,
                    backupURL: backupURL
                )
            } catch {
                deferredInitializationFailure = Self.recoveryBackupFailureMessage(error)
            }
            return
        }

        // init 中补齐终端能力不会触发任何 didSet。配置文件缺失或损坏时必须
        // 静默补写，否则扩展会把不支持 CLI 的终端菜单显示为可用。损坏或更高
        // 版本的文件会在上方进入只读恢复状态，绝不在这里覆盖。
        let wasMigrated: Bool
        if case .migrated = loadResult {
            wasMigrated = true
        } else {
            wasMigrated = false
        }
        if loaded != initial || wasMigrated {
            do {
                try save(initial, configurationURL)
            } catch {
                deferredInitializationFailure = Self.saveFailureMessage(error)
            }
        }
    }

    /// SwiftUI TextField 逐字符更新配置；落盘必须合并，避免把半个命令名下发给
    /// 每次右键都会重读配置的 Finder 扩展。离散操作改用 ``updateImmediately``。
    func replace(with updated: MenuConfiguration) {
        guard updated != configuration else { return }
        configuration = updated
        onChange?(updated)
        schedulePersist()
    }

    func updateImmediately(_ body: (inout MenuConfiguration) -> Void) {
        var updated = configuration
        body(&updated)
        guard updated != configuration else { return }
        configuration = updated
        onChange?(updated)
        pendingPersist?.cancel()
        pendingPersist = nil
        persist(reportStatus: true)
    }

    /// Toggle、增删、排序等直接绑定产生的离散变化会先进入节流队列，再由 UI
    /// 调用这里立即提交。没有待写入内容时不重复写盘。
    func persistImmediately() {
        flushPendingPersist(reportStatus: true)
    }

    /// 设置页关闭和 App 退出时同步冲刷，不能丢掉用户最后 400ms 的输入。
    /// 退出冲刷保持静默，避免临终状态覆盖最近一次有意义的动作结果。
    func flushPendingPersist() {
        flushPendingPersist(reportStatus: false)
    }

    func deliverDeferredInitializationFailure() {
        guard let message = deferredInitializationFailure else { return }
        deferredInitializationFailure = nil
        onFailure?(message)
    }

    var requiresConfigurationRecovery: Bool { recoveryFailure != nil }

    func exportSettingsData() throws -> Data {
        try MenuConfigurationTransfer.exportData(configuration)
    }

    /// 导入前先保存当前原始文件；只有备份和新配置落盘都成功后才解除恢复状态。
    func importSettingsData(_ data: Data) throws {
        let imported = try MenuConfigurationTransfer.importData(
            data,
            preservingLocalStateFrom: configuration
        )
        _ = try backupExistingConfiguration(configurationURL)
        try save(imported, configurationURL)
        pendingPersist?.cancel()
        pendingPersist = nil
        recoveryFailure = nil
        configuration = imported
        onChange?(imported)
    }

    /// 用户明确选择重置时才允许替换无法解析的原始文件，并且仍先做备份。
    func resetAfterRecovery() throws {
        guard recoveryFailure != nil else { return }
        _ = try backupExistingConfiguration(configurationURL)
        var reset = MenuConfiguration.default
        reset.terminalProfileID = configuration.terminalProfileID
        try save(reset, configurationURL)
        recoveryFailure = nil
        configuration = reset
        onChange?(reset)
    }

    /// 宿主界面每次真正呈现时都调用同步，让新增与删除无需进入设置页即可生效。
    /// 模板集合通常不变，此时镜像同步仍会完成清理，但不会重写 menu.json，
    /// 也不会用“已同步”覆盖最近一次有意义的动作状态。
    func refreshCustomTemplates() async {
        guard recoveryFailure == nil else { return }
        guard !isRefreshingCustomTemplates else { return }
        isRefreshingCustomTemplates = true
        defer { isRefreshingCustomTemplates = false }
        let existing = configuration.customTemplates
        let sourceDirectory = customTemplatesDirectory
        let mirrorDirectory = MenuConfigurationFile.mirroredTemplatesDirectory(
            configurationURL: configurationURL
        )
        let synchronizeTemplates = synchronizeTemplates
        do {
            let result = try await Task.detached(priority: .utility) {
                try synchronizeTemplates(
                    existing,
                    sourceDirectory,
                    mirrorDirectory
                )
            }.value
            if result.templates != configuration.customTemplates {
                updateImmediately { $0.customTemplates = result.templates }
                onStatus?(L10n.format(
                    "status.synced_templates",
                    fallback: "已同步 %lld 个自定义模板",
                    Int64(result.templates.count)
                ))
            }
            for filename in result.skippedOversizedFilenames {
                onFailure?(
                    TemplateMirrorError.templateTooLarge(filename)
                        .localizedDescription
                )
            }
        } catch {
            onFailure?(L10n.format(
                "error.sync_templates",
                fallback: "无法同步自定义模板：%@",
                error.localizedDescription
            ))
        }
    }

    private func schedulePersist() {
        pendingPersist?.cancel()
        pendingPersist = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: persistenceDelay)
            guard !Task.isCancelled else { return }
            pendingPersist = nil
            persist(reportStatus: false)
        }
    }

    private func flushPendingPersist(reportStatus: Bool) {
        guard pendingPersist != nil else { return }
        pendingPersist?.cancel()
        pendingPersist = nil
        persist(reportStatus: reportStatus)
    }

    private func persist(reportStatus: Bool) {
        guard recoveryFailure == nil else {
            onFailure?(Self.recoveryRequiredMessage())
            return
        }
        do {
            try save(configuration, configurationURL)
            if reportStatus {
                onStatus?(L10n.text(
                    "status.menu_saved",
                    fallback: "Finder 菜单设置已保存"
                ))
            }
        } catch {
            onFailure?(Self.saveFailureMessage(error))
        }
    }

    private static func saveFailureMessage(_ error: Error) -> String {
        L10n.format(
            "error.save_menu",
            fallback: "无法保存 Finder 菜单设置：%@",
            error.localizedDescription
        )
    }

    private static func recoveryFailureMessage(
        _ failure: MenuConfigurationLoadFailure?,
        backupURL: URL?
    ) -> String {
        let reason: String = switch failure {
        case .corrupted:
            L10n.text(
                "error.menu_configuration_corrupted",
                fallback: "Finder 菜单配置已损坏。"
            )
        case let .unsupportedVersion(version):
            L10n.format(
                "error.menu_configuration_newer",
                fallback: "Finder 菜单配置来自较新的版本（v%lld）。",
                Int64(version)
            )
        case .unreadable:
            L10n.text(
                "error.menu_configuration_unreadable",
                fallback: "Finder 菜单配置无法读取。"
            )
        case nil:
            L10n.text(
                "error.menu_configuration_invalid",
                fallback: "Finder 菜单配置无效。"
            )
        }
        guard let backupURL else {
            return reason + " " + recoveryRequiredMessage()
        }
        return L10n.format(
            "error.menu_configuration_recovery_with_backup",
            fallback: "%@ 已备份到 %@；导入有效设置或明确重置前不会覆盖原文件。",
            reason,
            backupURL.path
        )
    }

    private static func recoveryBackupFailureMessage(_ error: Error) -> String {
        L10n.format(
            "error.menu_configuration_backup",
            fallback: "配置异常且无法创建恢复备份：%@。原文件不会被覆盖。",
            error.localizedDescription
        )
    }

    private static func recoveryRequiredMessage() -> String {
        L10n.text(
            "error.menu_configuration_recovery_required",
            fallback: "请导入有效设置或在设置中明确重置后再修改。"
        )
    }
}
