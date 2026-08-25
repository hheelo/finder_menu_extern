import SwiftUI
import RightClickAppLogic
import RightClickCore

struct ContentView: View {
    let updater: UpdaterController
    @EnvironmentObject private var model: AppModel
    @State private var errorsExpanded = false
    @State private var confirmsFinderRestart = false

    var body: some View {
        ZStack {
            AppSurfaceBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appHeader
                    featureGrid
                    statusPanel
                    footer
                    errorHistory
                }
                .padding(28)
            }
        }
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
        HStack(spacing: 16) {
            AppIconMark(size: 58)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("RightClick")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    if let version = AppVersion.current {
                        Text(version.displayString)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.10), in: Capsule())
                            .textSelection(.enabled)
                            .accessibilityLabel(version.accessibilityLabel)
                    }
                }
                Text(L10n.text(
                    "home.subtitle",
                    fallback: "给 Finder 右键菜单加上开发者常用操作"
                ))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            StatusBadge(
                title: model.extensionEnabled
                    ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                    : L10n.text("home.extension_disabled", fallback: "还差一步：请在系统设置中启用扩展"),
                systemImage: model.extensionEnabled
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill",
                tint: model.extensionEnabled ? .green : .orange
            )
        }
    }

    private var featureGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            FeatureCard(
                icon: "doc.on.doc",
                title: L10n.text("home.feature.copy_title", fallback: "复制"),
                detail: L10n.text(
                    "home.feature.copy_detail",
                    fallback: "文件路径、文件名；支持多选"
                )
            )
            FeatureCard(
                icon: "rectangle.and.hand.point.up.left",
                title: L10n.text("home.feature.open_title", fallback: "打开"),
                detail: L10n.text(
                    "home.feature.open_detail",
                    fallback: "VS Code、ChatGPT 与更多编辑器"
                )
            )
            FeatureCard(
                icon: "terminal",
                title: L10n.text("home.feature.terminal_title", fallback: "终端"),
                detail: L10n.text(
                    "home.feature.terminal_detail",
                    fallback: "打开终端或运行 AI CLI"
                )
            )
            FeatureCard(
                icon: "doc.badge.plus",
                title: L10n.text("home.feature.create_title", fallback: "新建"),
                detail: L10n.text(
                    "home.feature.create_detail",
                    fallback: "内置与自定义模板、文件夹、剪贴板文本"
                )
            )
        }
    }

    private var statusPanel: some View {
        VisualPanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.extensionEnabled
                            ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                            : L10n.text(
                                "home.extension_disabled",
                                fallback: "还差一步：请在系统设置中启用扩展"
                            ))
                            .font(.headline)
                        Label(
                            diagnosticSummary,
                            systemImage: diagnosticAttentionCount == 0
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                            .font(.callout)
                            .foregroundStyle(
                                diagnosticAttentionCount == 0 ? .green : .orange
                            )
                    }
                    Spacer()
                    if model.isRefreshingDiagnostics {
                        ProgressView()
                            .controlSize(.small)
                            .help(L10n.text(
                                "home.diagnostics_refreshing",
                                fallback: "正在刷新诊断…"
                            ))
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        model.openExtensionSettings()
                    } label: {
                        Label(
                            model.extensionEnabled
                                ? L10n.text("button.manage_extension", fallback: "管理扩展")
                                : L10n.text("button.enable_extension", fallback: "启用 Finder 扩展"),
                            systemImage: "puzzlepiece.extension"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("rightclick.main.extension-settings")

                    Button {
                        confirmsFinderRestart = true
                    } label: {
                        Label(
                            L10n.text("button.restart_finder", fallback: "重启 Finder"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Label(model.lastStatus, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
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

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(
                    L10n.text("button.quit", fallback: "退出 RightClick"),
                    systemImage: "power"
                )
            }
            .accessibilityIdentifier("rightclick.main.quit")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
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

private struct FeatureCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.11))
                .clipShape(RoundedRectangle(
                    cornerRadius: AppVisualStyle.compactCornerRadius,
                    style: .continuous
                ))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(
            cornerRadius: AppVisualStyle.cornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: AppVisualStyle.cornerRadius,
                style: .continuous
            )
            .stroke(AppVisualStyle.panelStroke, lineWidth: 1)
        }
    }
}
