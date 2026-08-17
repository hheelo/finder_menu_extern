import Foundation
import RightClickCore

/// Finder 菜单配置的唯一宿主持有者。
///
/// 配置的加载、编辑、落盘和自定义模板同步都集中在这里；`AppModel` 只把
/// `onChange` 转发成 `@Published` 状态。这样新增配置项时不会再次把文件系统
/// 细节和界面状态混在一起。
@MainActor
final class MenuConfigurationStore {
    typealias Loader = (URL) -> MenuConfiguration
    typealias Saver = (MenuConfiguration, URL) throws -> Void
    typealias TemplateSynchronizer = @Sendable (
        _ existing: [CustomFileTemplate],
        _ sourceDirectory: URL,
        _ mirrorDirectory: URL
    ) throws -> [CustomFileTemplate]

    private(set) var configuration: MenuConfiguration
    var onChange: ((MenuConfiguration) -> Void)?
    var onStatus: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    let customTemplatesDirectory: URL

    private let configurationURL: URL
    private let save: Saver
    private let synchronizeTemplates: TemplateSynchronizer
    private let persistenceDelay: Duration
    private var pendingPersist: Task<Void, Never>?
    private var deferredInitializationFailure: String?
    private var isRefreshingCustomTemplates = false

    init(
        configurationURL: URL,
        customTemplatesDirectory: URL,
        terminalProfileID: String,
        load: Loader = { MenuConfigurationFile.load(from: $0) },
        save: @escaping Saver = {
            try MenuConfigurationFile.saveForHost($0, to: $1)
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
        self.persistenceDelay = persistenceDelay
        self.synchronizeTemplates = synchronizeTemplates

        let loaded = load(configurationURL)
        var initial = loaded
        initial.terminalProfileID = terminalProfileID
        configuration = initial

        // init 中补齐终端能力不会触发任何 didSet。配置文件缺失或损坏时必须
        // 静默补写，否则扩展会把不支持 CLI 的终端菜单显示为可用。
        if loaded != initial {
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

    /// 宿主界面每次真正呈现时都调用同步，让新增与删除无需进入设置页即可生效。
    /// 模板集合通常不变，此时镜像同步仍会完成清理，但不会重写 menu.json，
    /// 也不会用“已同步”覆盖最近一次有意义的动作状态。
    func refreshCustomTemplates() async {
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
            let templates = try await Task.detached(priority: .utility) {
                try synchronizeTemplates(
                    existing,
                    sourceDirectory,
                    mirrorDirectory
                )
            }.value
            guard templates != configuration.customTemplates else { return }
            updateImmediately { $0.customTemplates = templates }
            onStatus?(L10n.format(
                "status.synced_templates",
                fallback: "已同步 %lld 个自定义模板",
                Int64(templates.count)
            ))
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
}
