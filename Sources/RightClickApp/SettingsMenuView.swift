import SwiftUI
import RightClickAppServices
import RightClickCore

extension SettingsView {
    var menuSettings: some View {
        Form {
            finderMenuSection
            menuActionsSection
            monitoredDirectoriesSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    var finderMenuSection: some View {
        Section {
            Toggle(
                L10n.text(
                    "settings.collapse_menu",
                    fallback: "收进一个 RightClick 子菜单"
                ),
                isOn: $model.menuConfiguration.collapseIntoSubmenu
            )
            .focused($focusedControl, equals: .collapseMenu)
            .accessibilityIdentifier("rightclick.settings.menu.collapse")
            .onChange(of: model.menuConfiguration.collapseIntoSubmenu) {
                model.persistMenuConfigurationImmediately()
            }
            Picker(
                L10n.text("settings.copy_separator", fallback: "多选复制时分隔符"),
                selection: $model.clipboardSeparator
            ) {
                ForEach(ClipboardSeparator.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.finder_menu", fallback: "Finder 菜单"),
                systemImage: "list.bullet.rectangle"
            )
        } footer: {
            SettingsFootnote(L10n.text(
                "settings.menu_immediate_help",
                fallback: "修改后下一次打开 Finder 右键菜单立即生效，无需重启 Finder。"
            ))
        }
    }

    @ViewBuilder
    var menuActionsSection: some View {
        Section {
            // 菜单项有二十余条。放进一个限高的原生列表里，既保住 onMove 的
            // 拖拽排序，又不会把这一页撑成一条长得看不到头的开关阵列。
            List {
                ForEach(model.configuredMenuActions, id: \.configurationID) { action in
                    Toggle(
                        action.title,
                        isOn: Binding(
                            get: { model.menuActionIsEnabled(action) },
                            set: { model.setMenuAction(action, isEnabled: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                }
                .onMove(perform: model.moveMenuActions)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(height: menuActionListHeight)
            // 系统设置里的「登录项」也是这样：分组卡片内部再嵌一口更深的井，
            // 让可拖拽区域的边界一眼可见。
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        AppVisualStyle.panelStroke,
                        lineWidth: AppVisualStyle.hairline
                    )
            }
            .padding(.vertical, 2)

            HStack {
                Text(L10n.text(
                    "settings.drag_to_reorder",
                    fallback: "拖动菜单项可调整顺序。"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text(
                    "button.restore_default_order",
                    fallback: "恢复默认排序"
                )) {
                    model.restoreDefaultMenuActionOrder()
                }
                .disabled(model.menuConfiguration.actionOrder.isEmpty)
            }
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.menu_actions", fallback: "菜单项"),
                systemImage: "line.3.horizontal"
            )
        }
    }

    @ViewBuilder
    var monitoredDirectoriesSection: some View {
        Section {
            if model.menuConfiguration.monitoredDirectories.isEmpty {
                Label(
                    L10n.text(
                        "settings.monitor_all_directories",
                        fallback: "所有目录（/）"
                    ),
                    systemImage: "externaldrive.fill"
                )
            } else {
                ForEach(
                    model.menuConfiguration.monitoredDirectories,
                    id: \.self
                ) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeMonitoredDirectory(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.text(
                            "button.remove_monitored_directory",
                            fallback: "移除监控目录"
                        ))
                        .accessibilityLabel(L10n.text(
                            "button.remove_monitored_directory",
                            fallback: "移除监控目录"
                        ))
                    }
                }
            }

            HStack {
                Button(L10n.text(
                    "button.add_monitored_directory",
                    fallback: "添加目录"
                )) {
                    model.addMonitoredDirectories()
                }
                if !model.menuConfiguration.monitoredDirectories.isEmpty {
                    Button(L10n.text(
                        "button.monitor_all_directories",
                        fallback: "恢复监控所有目录"
                    )) {
                        model.monitorAllDirectories()
                    }
                }
                Spacer()
                Button(L10n.text(
                    "button.restart_finder_apply",
                    fallback: "重启 Finder 以应用"
                )) {
                    confirmsFinderRestart = true
                }
            }
        } header: {
            SettingsSectionHeader(
                title: L10n.text(
                    "settings.monitored_directories",
                    fallback: "Finder 监控目录"
                ),
                systemImage: "folder.badge.gearshape"
            )
        } footer: {
            SettingsFootnote(L10n.text(
                "settings.monitored_directories_help",
                fallback: "RightClick 只在这些目录及其子目录中显示。修改后需要重启 Finder；移除最后一项会恢复监控所有目录。不可用的外置磁盘路径会在扩展启动时跳过。"
            ))
        }
    }
}
