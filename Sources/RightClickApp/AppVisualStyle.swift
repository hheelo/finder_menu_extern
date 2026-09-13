import AppKit
import SwiftUI

/// 界面统一的尺寸与配色。数值对齐系统设置里的分组卡片，让宿主窗口、设置窗口
/// 和首次向导共用同一套节奏。
enum AppVisualStyle {
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 22
    static let rowHorizontalPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 11
    static let rowIconSize: CGFloat = 28
    static let rowIconSpacing: CGFloat = 12
    /// 行内文字相对卡片左边缘的缩进，行间分隔线按它对齐。
    static let rowTextInset = rowHorizontalPadding + rowIconSize + rowIconSpacing

    static let subtleFill = Color(nsColor: .controlBackgroundColor)
    static let panelStroke = Color(nsColor: .separatorColor)
    /// 1pt 描边在 Retina 上是两个物理像素，比系统卡片的发丝线明显更重。
    static let hairline: CGFloat = 0.5
}

struct AppSurfaceBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct AppIconMark: View {
    var size: CGFloat = 52

    var body: some View {
        // 应用图标自带高光与投影，再叠一层阴影会比系统「关于」面板更脏。
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 系统设置风格的分组卡片：填充用 control 背景色，边框是一根发丝线。
struct VisualPanel<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(
        padding: CGFloat = AppVisualStyle.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: AppVisualStyle.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(AppVisualStyle.subtleFill) }
            // strokeBorder 向内描边，1pt 的 stroke 会有一半溢出到填充之外。
            .overlay {
                shape.strokeBorder(
                    AppVisualStyle.panelStroke,
                    lineWidth: AppVisualStyle.hairline
                )
            }
    }
}

/// 带标题的分组：标题在卡片外，和系统设置的分组标题位置一致。
struct SectionBox<Content: View>: View {
    private let title: String
    private let padding: CGFloat
    private let content: Content

    init(
        _ title: String,
        padding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.leading, 2)
            VisualPanel(padding: padding) { content }
        }
    }
}

/// 卡片内的行间分隔线，默认与行内文字左对齐。
struct PanelDivider: View {
    var inset: CGFloat = AppVisualStyle.rowTextInset

    var body: some View {
        Divider()
            .padding(.leading, inset)
    }
}

/// 卡片内单行的统一内边距。
struct PanelRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, AppVisualStyle.rowHorizontalPadding)
            .padding(.vertical, AppVisualStyle.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TintIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = AppVisualStyle.rowIconSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
                .fill(tint.gradient)
            }
            .accessibilityHidden(true)
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}

/// 分组下方的说明文字。放在 Section 的 footer 里，由系统排在卡片之外，
/// 不再占用一行控件位置。
struct SettingsFootnote: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
