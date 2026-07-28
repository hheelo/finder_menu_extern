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
                        detail: "在项目目录运行 Codex CLI 或 Claude Code"
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
                Button("打开扩展设置") {
                    model.openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)

                Text("安装后需要在“登录项与扩展”中启用 Finder 扩展")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Label(model.lastStatus, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastError = model.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .lineLimit(2)
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
