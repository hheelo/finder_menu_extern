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

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        appHeader
                        featureGrid
                        statusPanel
                        errorHistory
                    }
                    .frame(maxWidth: 880)
                    .padding(.horizontal, 36)
                    .padding(.top, 34)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                }

                Divider()
                    .opacity(0.6)
                footer
                    .padding(.horizontal, 34)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial)
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
        HStack(spacing: 20) {
            AppIconMark(size: 72)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("RightClick")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .tracking(-0.7)
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
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            StatusBadge(
                title: model.extensionEnabled
                    ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                    : L10n.text("button.enable_extension", fallback: "启用 Finder 扩展"),
                systemImage: model.extensionEnabled
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill",
                tint: model.extensionEnabled ? .green : .orange
            )
        }
        .padding(.horizontal, 4)
    }

    private var featureGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 300), spacing: 12)
            ],
            spacing: 12
        ) {
            FeatureCard(
                icon: "doc.on.doc",
                tint: .blue,
                title: L10n.text("home.feature.copy_title", fallback: "复制"),
                detail: L10n.text(
                    "home.feature.copy_detail",
                    fallback: "文件路径、文件名；支持多选"
                )
            )
            FeatureCard(
                icon: "rectangle.and.hand.point.up.left",
                tint: .purple,
                title: L10n.text("home.feature.open_title", fallback: "打开"),
                detail: L10n.text(
                    "home.feature.open_detail",
                    fallback: "VS Code、ChatGPT 与更多编辑器"
                )
            )
            FeatureCard(
                icon: "terminal",
                tint: .indigo,
                title: L10n.text("home.feature.terminal_title", fallback: "终端"),
                detail: L10n.text(
                    "home.feature.terminal_detail",
                    fallback: "打开终端或运行 AI CLI"
                )
            )
            FeatureCard(
                icon: "doc.badge.plus",
                tint: .teal,
                title: L10n.text("home.feature.create_title", fallback: "新建"),
                detail: L10n.text(
                    "home.feature.create_detail",
                    fallback: "内置与自定义模板、文件夹、剪贴板文本"
                )
            )
        }
    }

    private var statusPanel: some View {
        let statusTint: Color = model.extensionEnabled ? .green : .orange

        return VisualPanel(tint: statusTint) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    TintIcon(
                        systemImage: model.extensionEnabled
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill",
                        tint: statusTint,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.extensionEnabled
                            ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                            : L10n.text(
                                "home.extension_disabled",
                                fallback: "还差一步：请在系统设置中启用扩展"
                            ))
                            .font(.title3.weight(.semibold))
                            .tracking(-0.2)
                        Label(
                            diagnosticSummary,
                            systemImage: diagnosticAttentionCount == 0
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
                    .opacity(0.65)

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
                    .controlSize(.large)
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
                    .controlSize(.large)

                    Spacer()

                    Label(model.lastStatus, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            SettingsLink {
                Label(
                    L10n.text("button.settings", fallback: "设置…"),
                    systemImage: "gearshape"
                )
            }
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityIdentifier("rightclick.main.settings")
            .buttonStyle(.bordered)

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
            .buttonStyle(.borderless)

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
            .buttonStyle(.borderless)

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
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.horizontal, 2)
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
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            TintIcon(systemImage: icon, tint: tint, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
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
        .shadow(color: Color.black.opacity(0.035), radius: 8, y: 4)
    }
}
