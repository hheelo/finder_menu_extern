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
    typealias TemplateSynchronizer = (
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

    init(
        configurationURL: URL,
        customTemplatesDirectory: URL,
        terminalProfileID: String,
        load: Loader = { MenuConfigurationFile.load(from: $0) },
        save: @escaping Saver = {
            try MenuConfigurationFile.saveForHost($0, to: $1)
        },
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
        self.synchronizeTemplates = synchronizeTemplates

        var initial = load(configurationURL)
        initial.terminalProfileID = terminalProfileID
        configuration = initial
    }

    func replace(with updated: MenuConfiguration) {
        guard updated != configuration else { return }
        configuration = updated
        onChange?(updated)
        persist()
    }

    func update(_ body: (inout MenuConfiguration) -> Void) {
        var updated = configuration
        body(&updated)
        replace(with: updated)
    }

    /// 宿主界面每次真正呈现时都调用同步，让新增与删除无需进入设置页即可生效。
    /// 模板集合通常不变，此时镜像同步仍会完成清理，但不会重写 menu.json，
    /// 也不会用“已同步”覆盖最近一次有意义的动作状态。
    func refreshCustomTemplates() {
        do {
            let templates = try synchronizeTemplates(
                configuration.customTemplates,
                customTemplatesDirectory,
                MenuConfigurationFile.mirroredTemplatesDirectory(
                    configurationURL: configurationURL
                )
            )
            guard templates != configuration.customTemplates else { return }
            update { $0.customTemplates = templates }
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

    private func persist() {
        do {
            try save(configuration, configurationURL)
            onStatus?(L10n.text(
                "status.menu_saved",
                fallback: "Finder 菜单设置已保存"
            ))
        } catch {
            onFailure?(L10n.format(
                "error.save_menu",
                fallback: "无法保存 Finder 菜单设置：%@",
                error.localizedDescription
            ))
        }
    }
}
