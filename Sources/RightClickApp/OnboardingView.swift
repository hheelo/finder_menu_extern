import SwiftUI
import RightClickCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step = 0
    @State private var pollingStopped = false
    @ScaledMetric(relativeTo: .title) private var appIconSize = 30
    @ScaledMetric(relativeTo: .body) private var stepContentMinHeight = 235
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: appIconSize))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text(
                        "onboarding.title",
                        fallback: "欢迎使用 RightClick"
                    ))
                        .font(.title.bold())
                    Text(L10n.format(
                        "onboarding.progress",
                        fallback: "第 %1$lld 步，共 %2$lld 步",
                        Int64(step + 1),
                        Int64(3)
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
            .frame(minHeight: stepContentMinHeight)

            HStack {
                Button(L10n.text(
                    "button.onboarding_later",
                    fallback: "稍后再说"
                )) {
                    model.skipOnboarding()
                }
                if step > 0 {
                    Button(L10n.text("button.back", fallback: "返回")) {
                        step -= 1
                    }
                }
                Spacer()
                if step < 2 {
                    Button(L10n.text(
                        "button.continue",
                        fallback: "继续"
                    )) {
                        step += 1
                        if step == 1 {
                            Task { await model.refreshDiagnostics(force: true) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 0 && !model.extensionEnabled)
                } else {
                    Button(L10n.text(
                        "button.finish",
                        fallback: "完成"
                    )) {
                        model.completeOnboarding()
                    }
                    Button(L10n.text(
                        "button.finish_open_settings",
                        fallback: "完成并打开设置"
                    )) {
                        model.completeOnboarding()
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(
            minWidth: 480,
            idealWidth: 540,
            minHeight: 380,
            idealHeight: 430
        )
        .interactiveDismissDisabled()
        .task {
            // 系统设置在另一个进程中修改扩展开关。旧系统每次检测都要启动
            // pluginkit，因此逐步退避并在五分钟后交给用户手动刷新。
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(
                by: OnboardingPollingPolicy.maximumDuration
            )
            var attempt = 0
            while !Task.isCancelled,
                  !model.extensionEnabled,
                  clock.now < deadline {
                await model.refreshExtensionStatus()
                let interval = OnboardingPollingPolicy.nextPollInterval(
                    attempt: attempt
                )
                attempt += 1
                let remaining = clock.now.duration(to: deadline)
                guard remaining > .zero else { break }
                try? await Task.sleep(for: min(interval, remaining))
            }
            if !Task.isCancelled && !model.extensionEnabled {
                pollingStopped = true
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    L10n.text(
                        "onboarding.extension_title",
                        fallback: "启用 Finder 扩展"
                    ),
                    systemImage: "puzzlepiece.extension"
                )
                    .font(.title3.bold())
                Text(L10n.text(
                    "onboarding.extension_detail",
                    fallback: "RightClick 需要 Finder 扩展才能把操作加入右键菜单。系统设置打开后，请启用 RightClick Finder Extension。"
                ))
                    .foregroundStyle(.secondary)
                Button(model.extensionEnabled
                    ? L10n.text("button.manage_extension", fallback: "管理扩展")
                    : L10n.text(
                        "button.enable_extension",
                        fallback: "启用 Finder 扩展"
                    )) {
                    model.openExtensionSettings()
                }
                Label(
                    model.extensionEnabled
                        ? L10n.text(
                            "onboarding.extension_ready",
                            fallback: "扩展已启用，可以继续"
                        )
                        : L10n.text(
                            "onboarding.extension_waiting",
                            fallback: "正在等待扩展启用…"
                        ),
                    systemImage: model.extensionEnabled
                        ? "checkmark.circle.fill"
                        : "clock"
                )
                    .foregroundStyle(model.extensionEnabled ? .green : .secondary)
                if pollingStopped && !model.extensionEnabled {
                    Button(L10n.text(
                        "onboarding.refresh_extension",
                        fallback: "刷新扩展状态"
                    )) {
                        Task { await model.refreshExtensionStatus() }
                    }
                }
            }
        case 1:
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    L10n.text(
                        "onboarding.terminal_title",
                        fallback: "选择默认终端"
                    ),
                    systemImage: "terminal"
                )
                    .font(.title3.bold())
                Text(L10n.text(
                    "onboarding.terminal_detail",
                    fallback: "“在终端中打开”和 AI CLI 动作会使用这个终端。未安装的终端会安全回退到 Terminal。"
                ))
                    .foregroundStyle(.secondary)
                Picker(
                    L10n.text("settings.terminal_picker", fallback: "默认终端"),
                    selection: $model.terminalProfile
                ) {
                    ForEach(TerminalProfile.selectableCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                if let terminalDiagnostic = model.diagnostics.first(where: {
                    $0.id == "default-terminal"
                }) {
                    Label(
                        terminalDiagnostic.detail,
                        systemImage: terminalDiagnostic.passed
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                        .foregroundStyle(
                            terminalDiagnostic.passed ? .green : .orange
                        )
                        .lineLimit(2)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                Label(
                    L10n.text(
                        "onboarding.try_title",
                        fallback: "现在去 Finder 试一下"
                    ),
                    systemImage: "hand.point.up.left.fill"
                )
                    .font(.title3.bold())
                Text(L10n.text(
                    "onboarding.try_detail",
                    fallback: "在 Finder 中右键任意文件或文件夹，就能看到复制、编辑器、终端和新建文件等操作。"
                ))
                    .foregroundStyle(.secondary)
                Label(
                    L10n.text(
                        "onboarding.permissions_detail",
                        fallback: "通知与终端自动化权限只会在相关操作首次需要时询问，不会在向导中提前请求。"
                    ),
                    systemImage: "hand.raised"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.text(
                    "onboarding.settings_hint",
                    fallback: "设置中还可以调整菜单、监控目录、自定义 CLI 和文件模板。"
                ))
                    .font(.callout)
            }
        }
    }
}
