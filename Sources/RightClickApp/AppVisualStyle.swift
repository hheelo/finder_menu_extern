import SwiftUI

enum AppVisualStyle {
    static let cornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 10
    static let panelStroke = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.035)
}

struct AppSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.accentColor.opacity(0.025),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct AppIconMark: View {
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: "cursorarrow.click.2")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 1)
            }
            .shadow(color: Color.accentColor.opacity(0.22), radius: 10, y: 5)
            .accessibilityHidden(true)
    }
}

struct VisualPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial)
            .background(AppVisualStyle.subtleFill)
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

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            }
    }
}

struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .textCase(nil)
    }
}
