import SwiftUI
import RightClickCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Finder 菜单") {
                Toggle(
                    "收进一个 RightClick 子菜单",
                    isOn: $model.menuConfiguration.collapseIntoSubmenu
                )
                ForEach(
                    Array(model.configuredMenuActions.enumerated()),
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
                        .help("上移")
                        Button {
                            model.moveMenuAction(action, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == model.configuredMenuActions.count - 1)
                        .help("下移")
                    }
                }
                Text("修改后下一次打开 Finder 右键菜单立即生效，无需重启 Finder。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("终端") {
                Picker("默认终端", selection: $model.terminalProfile) {
                    ForEach(TerminalProfile.selectableCases, id: \.self) { terminal in
                        Text(
                            terminal.title + (
                                terminal.supportsCLIExecution ? "" : "（仅打开目录）"
                            )
                        ).tag(terminal)
                    }
                }
                Picker("运行 AI CLI 时", selection: $model.terminalWindowBehavior) {
                    ForEach(TerminalWindowBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Text("「在终端中打开」与「运行 AI CLI」都使用默认终端。"
                    + "选自动时优先 iTerm2；未安装的终端回退到 Terminal。"
                    + "Warp 与 Ghostty 当前只支持打开目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自定义 AI CLI") {
                ForEach($model.menuConfiguration.cliProfiles) { $profile in
                    DisclosureGroup(profile.title) {
                        Toggle("显示在 Finder 菜单", isOn: $profile.isEnabled)
                        TextField("显示名称", text: $profile.title)
                        TextField("可执行名", text: $profile.executable)
                        ForEach(profile.arguments.indices, id: \.self) { index in
                            HStack {
                                TextField(
                                    "参数 \(index + 1)",
                                    text: $profile.arguments[index]
                                )
                                Button(role: .destructive) {
                                    profile.arguments.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        HStack {
                            Button("添加参数") {
                                profile.arguments.append("")
                            }
                            Spacer()
                            Button("删除配置", role: .destructive) {
                                model.removeCLIProfile(id: profile.id)
                            }
                        }
                    }
                }
                Button("添加 CLI 配置") {
                    model.addCLIProfile()
                }
                Text("深链只携带配置 ID；可执行名与参数保存在权限为 0600 的本机配置文件中。每个参数单独填写，不解析整行 shell 命令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自定义文件模板") {
                HStack {
                    Button("打开模板目录") {
                        model.openCustomTemplatesDirectory()
                    }
                    Button("刷新模板") {
                        model.refreshCustomTemplates()
                    }
                    Spacer()
                    Text("已同步 \(model.menuConfiguration.customTemplates.count) 个")
                        .foregroundStyle(.secondary)
                }
                Text("把文件放入 ~/Library/Application Support/RightClick/Templates/，刷新后会按原文件名出现在 Finder 的“新建文件”菜单中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("环境诊断") {
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
                    Button("重新检测") {
                        Task { await model.refreshDiagnostics(force: true) }
                    }
                    .disabled(model.isRefreshingDiagnostics)

                    if model.isRefreshingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    Button("复制诊断信息") {
                        model.copyDiagnostics()
                    }
                }
            }

            Section {
                Text(
                    "首次运行终端命令时，macOS 可能询问是否允许 "
                        + "RightClick 控制 Terminal 或 iTerm2。Finder 动作会在"
                        + "后台交给 RightClick 处理，不会显示宿主窗口。Terminal 的"
                        + "新标签页还需要允许 RightClick 使用辅助功能。"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
