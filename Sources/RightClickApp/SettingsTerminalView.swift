import SwiftUI
import RightClickCore

extension SettingsView {
    var terminalSettings: some View {
        Form {
            terminalSection
            cliSection
            securitySection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    var terminalSection: some View {
        Section {
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
            .focused($focusedControl, equals: .terminalProfile)
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
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.terminal", fallback: "终端"),
                systemImage: "terminal"
            )
        }

    }

    @ViewBuilder
    var cliSection: some View {
        Section {
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
                            .help(L10n.text(
                                "button.remove_argument",
                                fallback: "移除参数"
                            ))
                            .accessibilityLabel(L10n.text(
                                "button.remove_argument",
                                fallback: "移除参数"
                            ))
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
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.cli_title", fallback: "自定义 AI CLI"),
                systemImage: "chevron.left.forwardslash.chevron.right"
            )
        }

    }

    @ViewBuilder
    var securitySection: some View {
        Section {
            Text(L10n.text(
                "settings.security_help",
                fallback: "首次运行终端命令时，macOS 可能询问是否允许 RightClick 控制 Terminal 或 iTerm2。Finder 动作会在后台交给 RightClick 处理，不会显示宿主窗口。Terminal 的新标签页还需要允许 RightClick 使用辅助功能。"
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            SettingsSectionHeader(
                title: L10n.text("settings.security", fallback: "权限与安全"),
                systemImage: "lock.shield"
            )
        }

    }

}
