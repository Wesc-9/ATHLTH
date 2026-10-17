import SwiftUI

/// One visual language for Train Together discovery, scheduling, invitations,
/// lobby, live progress, meetup and chat. Presentation-only; no state changes.
enum ATHLTHTrainTogetherDesign {
    static let canvas = Color(red: 0.985, green: 0.982, blue: 0.972)
    static let surface = Color.white
    static let stone = ATHLTHTheme.cardWarm
    static let ink = ATHLTHTheme.primaryText
    static let secondary = ATHLTHTheme.mutedText
    static let accent = ATHLTHTheme.accentDeep
    static let accentSoft = ATHLTHTheme.accentSoft
    static let outline = ATHLTHTheme.accentDeep.opacity(0.105)
    static let radius: CGFloat = 22
    static let touchTarget: CGFloat = 48
}

private struct ATHLTHTrainTogetherCardChrome: ViewModifier {
    let radius: CGFloat
    let subtle: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            ATHLTHTrainTogetherDesign.surface,
                            subtle ? ATHLTHTrainTogetherDesign.surface
                                : ATHLTHTrainTogetherDesign.stone.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(ATHLTHTrainTogetherDesign.outline, lineWidth: 0.8)
            }
            .shadow(color: ATHLTHTrainTogetherDesign.accent.opacity(subtle ? 0.025 : 0.055),
                    radius: subtle ? 8 : 14, y: subtle ? 3 : 6)
    }
}

extension View {
    func athlthTrainTogetherCard(
        radius: CGFloat = ATHLTHTrainTogetherDesign.radius,
        subtle: Bool = false
    ) -> some View {
        modifier(ATHLTHTrainTogetherCardChrome(radius: radius, subtle: subtle))
    }
}

struct ATHLTHTrainTogetherSurface<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .athlthTrainTogetherCard()
    }
}

struct ATHLTHTrainTogetherSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHTrainTogetherDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(ATHLTHTrainTogetherDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
