import SwiftUI
import RightClickCore

extension SettingsView {
    var menuSettings: some View {
        List {
            finderMenuSection
            monitoredDirectoriesSection
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    var finderMenuSection: some View {
        let actions = model.configuredMenuActions
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
            ForEach(actions, id: \.configurationID) { action in
                Toggle(
                    action.title,
                    isOn: Binding(
                        get: { model.menuActionIsEnabled(action) },
                        set: { model.setMenuAction(action, isEnabled: $0) }
                    )
                )
            }
            .onMove(perform: model.moveMenuActions)
            HStack {
                Text(L10n.text(
                    "settings.drag_to_reorder",
                    fallback: "拖动菜单项可调整顺序。"
                ))
                    .font(.caption)
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
            Picker(
                L10n.text("settings.copy_separator", fallback: "多选复制时分隔符"),
                selection: $model.clipboardSeparator
            ) {
                ForEach(ClipboardSeparator.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            Text(L10n.text(
                "settings.menu_immediate_help",
                fallback: "修改后下一次打开 Finder 右键菜单立即生效，无需重启 Finder。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.finder_menu", fallback: "Finder 菜单"),
                systemImage: "list.bullet.rectangle"
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

            Text(L10n.text(
                "settings.monitored_directories_help",
                fallback: "RightClick 只在这些目录及其子目录中显示。修改后需要重启 Finder；移除最后一项会恢复监控所有目录。不可用的外置磁盘路径会在扩展启动时跳过。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                title: L10n.text(
                    "settings.monitored_directories",
                    fallback: "Finder 监控目录"
                ),
                systemImage: "folder.badge.gearshape"
            )
        }

    }

}
