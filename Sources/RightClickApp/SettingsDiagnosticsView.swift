import SwiftUI
import RightClickCore

extension SettingsView {
    var diagnosticSettings: some View {
        Form {
            applicationSection
            diagnosticsSection
            errorHistorySection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    var applicationSection: some View {
        Section(L10n.text("settings.application", fallback: "应用")) {
            if model.configurationRecoveryRequired {
                Label(
                    L10n.text(
                        "settings.configuration_recovery_required",
                        fallback: "菜单配置无法安全加载。导入有效设置或明确重置前，菜单编辑已暂停。"
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(
                L10n.text(
                    "settings.menu_bar_icon",
                    fallback: "在菜单栏显示 RightClick"
                ),
                isOn: $model.menuBarIconEnabled
            )
            .focused($focusedControl, equals: .menuBarIcon)
            Text(L10n.text(
                "settings.menu_bar_icon_help",
                fallback: "关闭主窗口后，可从菜单栏快速打开设置、复制诊断信息或重启 Finder。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.text(
                    "button.export_settings",
                    fallback: "导出设置…"
                )) {
                    model.exportSettings()
                }
                Button(L10n.text(
                    "button.import_settings",
                    fallback: "导入设置…"
                )) {
                    model.importSettings()
                }
                if model.configurationRecoveryRequired {
                    Button(
                        L10n.text("button.reset_settings", fallback: "重置设置"),
                        role: .destructive
                    ) {
                        confirmsConfigurationReset = true
                    }
                }
            }
            Text(L10n.text(
                "settings.settings_transfer_help",
                fallback: "导入导出包含菜单顺序、自定义 CLI 和内置模板选项；本机终端选择与自定义模板文件保持不变。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(L10n.text(
                "button.restart_onboarding",
                fallback: "重新运行首次向导"
            )) {
                model.restartOnboarding()
                WindowPresenter.showOrCreateMainWindow()
            }
            Text(L10n.text(
                "settings.restart_onboarding_help",
                fallback: "重新显示三步首次设置；现有菜单和终端配置不会被清除。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

    }

    @ViewBuilder
    var diagnosticsSection: some View {
        Section(L10n.text("settings.diagnostics", fallback: "环境诊断")) {
            ForEach(model.diagnostics) { item in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(item.passed
                            ? L10n.text(
                                "diagnostic.status_passed",
                                fallback: "通过"
                            )
                            : L10n.text(
                                "diagnostic.status_attention",
                                fallback: "需要注意"
                            ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                item.passed ? Color.green : Color.orange
                            )
                        Text(item.detail)
                            .foregroundStyle(
                                item.passed ? Color.secondary : Color.orange
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                .accessibilityElement(children: .combine)
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

    }

    @ViewBuilder
    var errorHistorySection: some View {
        if !model.errorHistory.isEmpty {
            Section(L10n.format(
                "home.errors",
                fallback: "最近错误（%lld）",
                Int64(model.errorHistory.count)
            )) {
                ForEach(model.errorHistory) { record in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(record.date, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(record.message)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack {
                    Spacer()
                    Button(L10n.text("button.clear", fallback: "清除")) {
                        model.clearErrors()
                    }
                }
            }
        }
    }

}
