import SwiftUI
import RightClickCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("终端") {
                Picker("默认终端", selection: $model.terminalProfile) {
                    ForEach(TerminalProfile.selectableCases, id: \.self) { terminal in
                        Text(terminal.title).tag(terminal)
                    }
                }
                Text("「在终端中打开」与「运行 AI CLI」都使用这里的选择。"
                    + "选自动时优先 iTerm2；未安装 iTerm2 时回退到 Terminal。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "运行 CLI 前切到前台确认",
                    isOn: $model.confirmCLIExecution
                )
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
                        + "RightClick 控制 Terminal 或 iTerm2。关闭确认时，"
                        + "Finder 操作不会将 RightClick 切到前台。"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
