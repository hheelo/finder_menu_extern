import AppKit
import SwiftUI

enum AppVisualStyle {
    static let cornerRadius: CGFloat = 16
    static let compactCornerRadius: CGFloat = 11
    static let panelStroke = Color.primary.opacity(0.075)
    static let subtleFill = Color.primary.opacity(0.025)
    static let elevatedShadow = Color.black.opacity(0.075)
}

struct AppSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.085),
                    Color.indigo.opacity(0.035),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.075),
                    .clear
                ],
                center: UnitPoint(x: 0.9, y: 0.05),
                startRadius: 0,
                endRadius: 360
            )
        }
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
            .shadow(color: Color.accentColor.opacity(0.18), radius: 14, y: 7)
            .accessibilityHidden(true)
    }
}

struct VisualPanel<Content: View>: View {
    private let tint: Color?
    private let padding: CGFloat
    private let content: Content

    init(
        tint: Color? = nil,
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
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
                .fill(.regularMaterial)
                .overlay {
                    if let tint {
                        LinearGradient(
                            colors: [tint.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    } else {
                        AppVisualStyle.subtleFill
                    }
                }
                .clipShape(RoundedRectangle(
                    cornerRadius: AppVisualStyle.cornerRadius,
                    style: .continuous
                ))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: AppVisualStyle.cornerRadius,
                    style: .continuous
                )
                .stroke(AppVisualStyle.panelStroke, lineWidth: 1)
            }
            .shadow(color: AppVisualStyle.elevatedShadow, radius: 12, y: 5)
    }
}

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
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
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.11), in: RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
                .stroke(tint.opacity(0.14), lineWidth: 1)
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
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(
                    cornerRadius: 6,
                    style: .continuous
                ))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .textCase(nil)
    }
}
