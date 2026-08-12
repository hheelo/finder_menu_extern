import SwiftUI
import RightClickCore

struct ContentView: View {
    let updater: UpdaterController
    @EnvironmentObject private var model: AppModel
    @State private var errorsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RightClick")
                        .font(.largeTitle.bold())
                    Text(L10n.text("home.subtitle", fallback: "给 Finder 右键菜单加上开发者常用操作"))
                        .foregroundStyle(.secondary)
                    if let version = AppVersion.current {
                        Text(version.displayString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .accessibilityLabel(version.accessibilityLabel)
                    }
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        icon: "doc.on.doc",
                        title: L10n.text("home.feature.copy_title", fallback: "复制"),
                        detail: L10n.text(
                            "home.feature.copy_detail",
                            fallback: "文件路径、文件名；支持多选"
                        )
                    )
                    FeatureRow(
                        icon: "rectangle.and.hand.point.up.left",
                        title: L10n.text("home.feature.open_title", fallback: "打开"),
                        detail: L10n.text(
                            "home.feature.open_detail",
                            fallback: "VS Code、ChatGPT 与更多编辑器"
                        )
                    )
                    FeatureRow(
                        icon: "terminal",
                        title: L10n.text("home.feature.terminal_title", fallback: "终端"),
                        detail: L10n.text(
                            "home.feature.terminal_detail",
                            fallback: "打开终端或运行 AI CLI"
                        )
                    )
                    FeatureRow(
                        icon: "doc.badge.plus",
                        title: L10n.text("home.feature.create_title", fallback: "新建"),
                        detail: L10n.text(
                            "home.feature.create_detail",
                            fallback: "内置与自定义模板、文件夹、剪贴板文本"
                        )
                    )
                }
                .padding(8)
            }

            HStack {
                Button(model.extensionEnabled
                    ? L10n.text("button.manage_extension", fallback: "管理扩展")
                    : L10n.text("button.enable_extension", fallback: "启用 Finder 扩展")) {
                    model.openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.text("button.restart_finder", fallback: "重启 Finder")) {
                    model.restartFinder()
                }
                .buttonStyle(.bordered)

                Label(
                    model.extensionEnabled
                        ? L10n.text("home.extension_enabled", fallback: "Finder 扩展已启用")
                        : L10n.text(
                            "home.extension_disabled",
                            fallback: "还差一步：请在系统设置中启用扩展"
                        ),
                    systemImage: model.extensionEnabled
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
                    .font(.callout)
                    .foregroundStyle(
                        model.extensionEnabled ? .green : .secondary
                    )
            }

            Divider()

            HStack {
                Label(model.lastStatus, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                // LSUIElement 附属应用没有可依赖的常驻菜单栏，必须在主窗口里
                // 提供明确入口，否则默认终端设置无法到达。
                SettingsLink {
                    Text(L10n.text("button.settings", fallback: "设置…"))
                }
                Button(L10n.text("button.check_updates", fallback: "检查更新")) {
                    updater.checkForUpdates()
                }
                Button(L10n.text("button.copy_diagnostics", fallback: "复制诊断信息")) {
                    model.copyDiagnostics()
                }
                // 附属应用没有 Dock 图标也没有菜单栏，必须给一个显式的退出入口，
                // 否则用户只能去活动监视器里结束进程。
                Button(L10n.text("button.quit", fallback: "退出 RightClick")) {
                    NSApp.terminate(nil)
                }
            }

            if !model.errorHistory.isEmpty {
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
                                HStack(
                                    alignment: .firstTextBaseline,
                                    spacing: 10
                                ) {
                                    Text(record.date, style: .time)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    // 扩展消息始终作为纯文本渲染，不识别链接。
                                    Text(record.message)
                                        .foregroundStyle(.red)
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .leading
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 6)
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
        .padding(28)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.tint)
            Text(title)
                .fontWeight(.semibold)
                .frame(width: 64, alignment: .leading)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}
