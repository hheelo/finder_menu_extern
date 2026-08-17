import SwiftUI
import RightClickCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let actions = model.configuredMenuActions
        Form {
            Section(L10n.text("settings.finder_menu", fallback: "Finder 菜单")) {
                Toggle(
                    L10n.text(
                        "settings.collapse_menu",
                        fallback: "收进一个 RightClick 子菜单"
                    ),
                    isOn: $model.menuConfiguration.collapseIntoSubmenu
                )
                .onChange(of: model.menuConfiguration.collapseIntoSubmenu) {
                    model.persistMenuConfigurationImmediately()
                }
                ForEach(
                    Array(actions.enumerated()),
                    id: \.element.configurationID
                ) { index, action in
                    HStack {
                        Toggle(
                            action.title,
                            isOn: Binding(
                                get: { model.menuActionIsEnabled(action) },
                                set: { model.setMenuAction(action, isEnabled: $0) }
                            )
                        )
                        Spacer()
                        Button {
                            model.moveMenuAction(action, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help(L10n.text("settings.move_up", fallback: "上移"))
                        Button {
                            model.moveMenuAction(action, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == actions.count - 1)
                        .help(L10n.text("settings.move_down", fallback: "下移"))
                    }
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
            }

            Section(L10n.text(
                "settings.monitored_directories",
                fallback: "Finder 监控目录"
            )) {
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
                        model.restartFinder()
                    }
                }

                Text(L10n.text(
                    "settings.monitored_directories_help",
                    fallback: "RightClick 只在这些目录及其子目录中显示。修改后需要重启 Finder；移除最后一项会恢复监控所有目录。不可用的外置磁盘路径会在扩展启动时跳过。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.terminal", fallback: "终端")) {
                Picker(
                    L10n.text("settings.terminal_picker", fallback: "默认终端"),
                    selection: $model.terminalProfile
                ) {
                    ForEach(TerminalProfile.selectableCases, id: \.self) { terminal in
                        Text(
                            terminal.title + (
                                terminal.supportsCLIExecution ? "" : L10n.text(
                                    "separator.only_open_directory",
                                    fallback: "（仅打开目录）"
                                )
                            )
                        ).tag(terminal)
                    }
                }
                Picker(
                    L10n.text("settings.run_cli_behavior", fallback: "运行 AI CLI 时"),
                    selection: $model.terminalWindowBehavior
                ) {
                    ForEach(TerminalWindowBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Text(L10n.text(
                    "settings.terminal_help",
                    fallback: "“在终端中打开”与“运行 AI CLI”都使用默认终端。选自动时优先 iTerm2；未安装的终端回退到 Terminal。Warp 与 Ghostty 当前只支持打开目录。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.application", fallback: "应用")) {
                Toggle(
                    L10n.text(
                        "settings.menu_bar_icon",
                        fallback: "在菜单栏显示 RightClick"
                    ),
                    isOn: $model.menuBarIconEnabled
                )
                Text(L10n.text(
                    "settings.menu_bar_icon_help",
                    fallback: "关闭主窗口后，可从菜单栏快速打开设置、复制诊断信息或重启 Finder。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.cli_title", fallback: "自定义 AI CLI")) {
                ForEach($model.menuConfiguration.cliProfiles) { $profile in
                    DisclosureGroup {
                        Toggle(L10n.text("settings.show_in_finder", fallback: "显示在 Finder 菜单"), isOn: $profile.isEnabled)
                            .onChange(of: profile.isEnabled) {
                                model.persistMenuConfigurationImmediately()
                            }
                        TextField(L10n.text("settings.display_name", fallback: "显示名称"), text: $profile.title)
                        TextField(L10n.text("settings.cli_executable", fallback: "命令名或绝对路径"), text: $profile.executable)
                        ForEach(
                            Array(profile.arguments.enumerated()),
                            id: \.offset
                        ) { index, _ in
                            HStack {
                                TextField(
                                    L10n.format(
                                        "settings.argument_number",
                                        fallback: "参数 %lld",
                                        Int64(index + 1)
                                    ),
                                    text: $profile.arguments[index]
                                )
                                Button(role: .destructive) {
                                    model.removeCLIArgument(
                                        profileID: profile.id,
                                        at: index
                                    )
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            Button(L10n.text("button.add_argument", fallback: "添加参数")) {
                                profile.arguments.append("")
                                model.persistMenuConfigurationImmediately()
                            }
                        }
                    } label: {
                        HStack {
                            Text(profile.title.isEmpty
                                ? L10n.text(
                                    "settings.default_cli_title",
                                    fallback: "自定义 CLI"
                                )
                                : profile.title)
                            Spacer()
                            Button(role: .destructive) {
                                model.removeCLIProfile(id: profile.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.text(
                                "button.delete_cli",
                                fallback: "删除配置"
                            ))
                            .accessibilityLabel(L10n.text(
                                "button.delete_cli",
                                fallback: "删除配置"
                            ))
                        }
                    }
                }
                Button(L10n.text("button.add_cli", fallback: "添加 CLI 配置")) {
                    model.addCLIProfile()
                }
                Text(L10n.text(
                    "settings.cli_security_help",
                    fallback: "可填写 PATH 中的命令名或可执行文件的绝对路径。深链只携带配置 ID；命令与参数保存在权限为 0600 的本机配置文件中。每个参数单独填写，不解析整行 shell 命令。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.templates", fallback: "自定义文件模板")) {
                HStack {
                    Button(L10n.text("button.open_templates", fallback: "打开模板目录")) {
                        model.openCustomTemplatesDirectory()
                    }
                    Button(L10n.text("button.refresh", fallback: "刷新模板")) {
                        Task { await model.refreshCustomTemplates() }
                    }
                    Spacer()
                    Text(L10n.format(
                        "settings.synced_templates",
                        fallback: "已同步 %lld 个",
                        Int64(model.menuConfiguration.customTemplates.count)
                    ))
                        .foregroundStyle(.secondary)
                }
                Text(L10n.text(
                    "settings.templates_help",
                    fallback: "把文件放入 ~/Library/Application Support/RightClick/Templates/，刷新后会按原文件名出现在 Finder 的“新建文件”菜单中。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text(
                "settings.builtin_templates",
                fallback: "内置文件模板"
            )) {
                ForEach(FileTemplate.allCases, id: \.rawValue) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(template.title)
                                .frame(width: 110, alignment: .leading)
                            TextField(
                                template.preferredFilename,
                                text: Binding(
                                    get: { model.templateFilename(for: template) },
                                    set: {
                                        model.setTemplateFilename($0, for: template)
                                    }
                                )
                            )
                            Picker(
                                "",
                                selection: Binding(
                                    get: { model.templateEncoding(for: template) },
                                    set: {
                                        model.setTemplateEncoding($0, for: template)
                                    }
                                )
                            ) {
                                ForEach(TemplateEncoding.allCases, id: \.self) {
                                    Text($0.title).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        let filename = model.templateFilename(for: template)
                        if !filename.isEmpty,
                           !FileCreator.isSafeFilename(filename) {
                            Text(L10n.text(
                                "settings.invalid_template_filename",
                                fallback: "文件名无效，将使用内置默认值。"
                            ))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text(L10n.text(
                    "settings.builtin_templates_help",
                    fallback: "文件名留空时使用内置默认值；非法文件名和未知编码会被安全忽略。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text("settings.diagnostics", fallback: "环境诊断")) {
                ForEach(model.diagnostics) { item in
                    LabeledContent {
                        Text(item.detail)
                            .foregroundStyle(
                                item.passed ? Color.secondary : Color.orange
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } label: {
                        Label(
                            item.title,
                            systemImage: item.passed
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            item.passed ? Color.green : Color.orange
                        )
                    }
                }

                HStack {
                    Button(L10n.text("button.recheck", fallback: "重新检测")) {
                        Task { await model.refreshDiagnostics(force: true) }
                    }
                    .disabled(model.isRefreshingDiagnostics)

                    if model.isRefreshingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button(L10n.text("button.copy_diagnostics", fallback: "复制诊断信息")) {
                        model.copyDiagnostics()
                    }

                    Button(L10n.text(
                        "button.export_local_log",
                        fallback: "导出本地日志…"
                    )) {
                        model.exportLocalActionLog()
                    }
                }

                Text(L10n.text(
                    "settings.local_log_help",
                    fallback: "导出时合并最近 200 条动作结果和异常终止标记；不记录文件路径、文件名、命令参数或深链内容。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(L10n.text(
                    "settings.security_help",
                    fallback: "首次运行终端命令时，macOS 可能询问是否允许 RightClick 控制 Terminal 或 iTerm2。Finder 动作会在后台交给 RightClick 处理，不会显示宿主窗口。Terminal 的新标签页还需要允许 RightClick 使用辅助功能。"
                ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    returnToMainWindow()
                } label: {
                    Label(
                        L10n.text("button.back", fallback: "返回"),
                        systemImage: "chevron.left"
                    )
                }
                .help(L10n.text("button.back", fallback: "返回"))
            }
        }
        .onDisappear {
            model.flushPendingMenuConfiguration()
        }
    }

    private func returnToMainWindow() {
        let mainWindowExists = WindowPresenter.hasMainWindow
        dismiss()
        if mainWindowExists {
            DispatchQueue.main.async {
                WindowPresenter.bringMainWindowToFront()
            }
        } else {
            openWindow(id: AppWindow.mainID)
        }
    }
}
