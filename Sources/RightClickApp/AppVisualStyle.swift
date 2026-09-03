import AppKit
import SwiftUI

enum AppVisualStyle {
    static let cornerRadius: CGFloat = 18
    static let compactCornerRadius: CGFloat = 10
    static let panelStroke = Color.primary.opacity(0.07)
    static let subtleFill = Color.primary.opacity(0.015)
    static let elevatedShadow = Color.black.opacity(0.045)
}

struct AppSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.055),
                    Color.accentColor.opacity(0.012),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.62, y: 0.68)
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.12),
                    .clear
                ],
                center: UnitPoint(x: 0.82, y: 0.02),
                startRadius: 0,
                endRadius: 480
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
            .shadow(color: Color.black.opacity(0.12), radius: 5, y: 3)
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
                            colors: [tint.opacity(0.045), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
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
            .shadow(color: AppVisualStyle.elevatedShadow, radius: 9, y: 4)
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
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
                .fill(tint)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: size * 0.28,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.20), lineWidth: 0.75)
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
