import SwiftUI
import RightClickAppLogic
import RightClickAppServices
import RightClickCore

struct ContentView: View {
    let updater: UpdaterController
    @EnvironmentObject private var model: AppModel
    @State private var errorsExpanded = false
    @State private var confirmsFinderRestart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appHeader
                featurePanel
                statusPanel
                errorHistory
            }
            .frame(maxWidth: 660)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .background(AppSurfaceBackground())
        .toolbar { appToolbar }
        .onAppear {
            AppSmokeTest.markReady()
        }
        .finderRestartConfirmation(isPresented: $confirmsFinderRestart) {
            model.restartFinder()
        }
        .sheet(isPresented: Binding(
            get: { model.shouldPresentOnboarding },
            set: { _ in }
        )) {
            OnboardingView {
                DispatchQueue.main.async {
                    WindowPresenter.showSettings()
                }
            }
            .environmentObject(model)
        }
    }

    private var appHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            AppIconMark(size: 60)
            VStack(alignment: .leading, spacing: 5) {
                Text("RightClick")
                    .font(.system(size: 24, weight: .semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text(
                        "home.subtitle",
                        fallback: "给 Finder 右键菜单加上开发者常用操作"
                    ))
                    if let version = AppVersion.current {
                        Text(version.displayString)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .textSelection(.enabled)
                            .accessibilityLabel(version.accessibilityLabel)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            VStack(alignment: .trailing, spacing: 9) {
                Label(
                    model.extensionEnabled
                        ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                        : L10n.text(
                            "home.extension_disabled_short",
                            fallback: "Finder 扩展未启用"
                        ),
                    systemImage: model.extensionEnabled
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle.fill"
                )
                .accessibilityIdentifier("rightclick.main.extension-status")
                .font(.caption.weight(.medium))
                .foregroundStyle(model.extensionEnabled ? .green : .orange)

                Button {
                    model.openExtensionSettings()
                } label: {
                    Text(model.extensionEnabled
                        ? L10n.text("button.manage_extension", fallback: "管理扩展")
                        : L10n.text("button.enable_extension", fallback: "启用 Finder 扩展"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("rightclick.main.extension-settings")
            }
        }
    }

    private var featurePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("home.features", fallback: "主要功能"))
                .font(.headline)

            VisualPanel(padding: 0) {
                VStack(spacing: 0) {
                    FeatureSummary(
                        icon: "doc.on.doc",
                        tint: .blue,
                        title: L10n.text("home.feature.copy_title", fallback: "复制"),
                        detail: L10n.text(
                            "home.feature.copy_detail",
                            fallback: "文件路径、文件名；支持多选"
                        )
                    )
                    Divider().padding(.leading, 60)
                    FeatureSummary(
                        icon: "rectangle.and.hand.point.up.left",
                        tint: .purple,
                        title: L10n.text("home.feature.open_title", fallback: "打开"),
                        detail: L10n.text(
                            "home.feature.open_detail",
                            fallback: "VS Code、ChatGPT 与更多编辑器"
                        )
                    )
                    Divider().padding(.leading, 60)
                    FeatureSummary(
                        icon: "terminal",
                        tint: .teal,
                        title: L10n.text("home.feature.terminal_title", fallback: "终端"),
                        detail: L10n.text(
                            "home.feature.terminal_detail",
                            fallback: "打开终端或运行 AI CLI"
                        )
                    )
                    Divider().padding(.leading, 60)
                    FeatureSummary(
                        icon: "doc.badge.plus",
                        tint: .orange,
                        title: L10n.text("home.feature.create_title", fallback: "新建"),
                        detail: L10n.text(
                            "home.feature.create_detail",
                            fallback: "内置与自定义模板、文件夹、剪贴板文本"
                        )
                    )
                }
            }
        }
    }

    private var statusPanel: some View {
        let statusTint: Color = diagnosticAttentionCount == 0 ? .green : .orange

        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("settings.tab.diagnostics", fallback: "诊断"))
                .font(.headline)

            VisualPanel(padding: 0) {
                HStack(spacing: 14) {
                    TintIcon(
                        systemImage: diagnosticAttentionCount == 0
                            ? "checkmark"
                            : "exclamationmark",
                        tint: statusTint,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosticSummary)
                            .font(.body.weight(.medium))
                        Label(model.lastStatus, systemImage: "clock.arrow.circlepath")
                            .accessibilityIdentifier("rightclick.main.last-status")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 16)
                    if model.isRefreshingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                            .help(L10n.text(
                                "home.diagnostics_refreshing",
                                fallback: "正在刷新诊断…"
                            ))
                    }
                    Button {
                        confirmsFinderRestart = true
                    } label: {
                        Label(
                            L10n.text("button.restart_finder", fallback: "重启 Finder"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    @ToolbarContentBuilder
    private var appToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            SettingsLink {
                Label(
                    L10n.text("button.settings", fallback: "设置…"),
                    systemImage: "gearshape"
                )
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("rightclick.main.settings")

            Button {
                updater.checkForUpdates()
            } label: {
                Label(
                    L10n.text("button.check_updates", fallback: "检查更新"),
                    systemImage: "arrow.down.circle"
                )
            }
            .keyboardShortcut("u", modifiers: .command)
            .accessibilityIdentifier("rightclick.main.check-updates")
            .help(L10n.text("button.check_updates", fallback: "检查更新"))

            Button {
                model.copyDiagnostics()
            } label: {
                Label(
                    L10n.text("button.copy_diagnostics", fallback: "复制诊断信息"),
                    systemImage: "doc.on.clipboard"
                )
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .accessibilityIdentifier("rightclick.main.copy-diagnostics")
            .help(L10n.text("button.copy_diagnostics", fallback: "复制诊断信息"))
        }
    }

    @ViewBuilder
    private var errorHistory: some View {
        if !model.errorHistory.isEmpty {
            VisualPanel {
                DisclosureGroup(
                    L10n.format(
                        "home.errors",
                        fallback: "最近错误（%lld）",
                        Int64(model.errorHistory.count)
                    ),
                    isExpanded: $errorsExpanded
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
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
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 180)

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

    private var diagnosticAttentionCount: Int {
        model.diagnostics.count { !$0.passed }
    }

    private var diagnosticSummary: String {
        L10n.format(
            "home.diagnostics_summary",
            fallback: "%1$lld 项通过 / %2$lld 项需要注意",
            Int64(model.diagnostics.count - diagnosticAttentionCount),
            Int64(diagnosticAttentionCount)
        )
    }
}

private struct FeatureSummary: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            TintIcon(systemImage: icon, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
