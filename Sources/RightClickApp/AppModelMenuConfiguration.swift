import AppKit
import RightClickCore

@MainActor
extension AppModel {
    static func orderedActions(
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
}
