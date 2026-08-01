import SwiftUI
import RightClickCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 38))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RightClick")
                        .font(.largeTitle.bold())
                    Text("给 Finder 右键菜单加上开发者常用操作")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        icon: "doc.on.doc",
                        title: "复制",
                        detail: "文件路径、文件名；多选时每行一个"
                    )
                    FeatureRow(
                        icon: "rectangle.and.hand.point.up.left",
                        title: "打开",
                        detail: "Visual Studio Code、Codex"
                    )
                    FeatureRow(
                        icon: "terminal",
                        title: "终端",
                        detail: "用 Terminal / iTerm2 打开，或运行 AI CLI"
                    )
                    FeatureRow(
                        icon: "doc.badge.plus",
                        title: "新建",
                        detail: "TXT、Markdown、Python、Shell、HTML、JSON、CSV"
                    )
                }
                .padding(8)
            }

            HStack {
                Button(model.extensionEnabled ? "管理扩展" : "启用 Finder 扩展") {
                    model.openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("重启 Finder") {
                    model.restartFinder()
                }

                Label(
                    model.extensionEnabled
                        ? "Finder 扩展已启用"
                        : "还差一步：请在系统设置中启用扩展",
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
                Button("复制诊断信息") {
                    model.copyDiagnostics()
                }
                // 附属应用没有 Dock 图标也没有菜单栏，必须给一个显式的退出入口，
                // 否则用户只能去活动监视器里结束进程。
                Button("退出 RightClick") {
                    NSApp.terminate(nil)
                }
                if let lastError = model.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(28)
        .alert(
            "启动 CLI？",
            isPresented: Binding(
                get: { model.pendingInvocation != nil },
                set: { isPresented in
                    if !isPresented {
                        model.cancelPendingInvocation()
                    }
                }
            ),
            presenting: model.pendingInvocation
        ) { _ in
            Button("取消", role: .cancel) {
                model.cancelPendingInvocation()
            }
            Button("启动") {
                model.confirmPendingInvocation()
            }
        } message: { invocation in
            Text(
                "将在 \(model.terminalProfile.title) 中运行 "
                    + "\(invocation.command.title)：\n"
                    + invocation.workingDirectory.path
            )
        }
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
