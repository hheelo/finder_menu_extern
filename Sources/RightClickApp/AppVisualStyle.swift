import AppKit
import SwiftUI

enum AppVisualStyle {
    static let cornerRadius: CGFloat = 10
    static let compactCornerRadius: CGFloat = 8
    static let panelStroke = Color(nsColor: .separatorColor).opacity(0.30)
    static let subtleFill = Color(nsColor: .controlBackgroundColor)
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
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}

struct VisualPanel<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(
                    cornerRadius: AppVisualStyle.cornerRadius,
                    style: .continuous
                )
                .fill(AppVisualStyle.subtleFill)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: AppVisualStyle.cornerRadius,
                    style: .continuous
                )
                .stroke(AppVisualStyle.panelStroke, lineWidth: 1)
            }
    }
}

struct TintIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(
                    cornerRadius: size * 0.26,
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
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}
