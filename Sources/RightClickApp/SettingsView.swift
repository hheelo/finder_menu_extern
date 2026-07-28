import SwiftUI
import RightClickCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Picker("默认终端", selection: $model.terminalProfile) {
                ForEach(TerminalProfile.allCases, id: \.self) { terminal in
                    Text(terminal.title).tag(terminal)
                }
            }

            LabeledContent("Codex CLI 命令", value: "codex")
            LabeledContent("Claude Code 命令", value: "claude")

            Section {
                Text("首次运行终端命令时，macOS 可能询问是否允许 RightClick 控制 Terminal 或 iTerm2。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
