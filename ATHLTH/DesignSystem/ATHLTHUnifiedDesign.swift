import SwiftUI

/// Consistent high-contrast premium surfaces for secondary ATHLTH screens.
/// Intentionally mirrors ATHLTHCard's zero-spacing layout to preserve the
/// semantics of live metrics and controls already in each screen.
enum ATHLTHUnifiedDesign {
    static let canvas = ATHLTHPlanDesign.canvas
    static let ink = ATHLTHTheme.primaryText
    static let secondary = ATHLTHPlanDesign.secondaryInk
    static let accent = ATHLTHPlanDesign.accentInk
    static let outline = ATHLTHPlanDesign.outline
    static let surface = ATHLTHPlanDesign.surface
    static let selected = ATHLTHPlanDesign.selectedSurface
    static let radius: CGFloat = ATHLTHPlanDesign.cardRadius
}

struct ATHLTHUnifiedCard<Content: View>: View {
    var compact = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(compact ? 13 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: compact ? 17 : ATHLTHUnifiedDesign.radius,
                style: .continuous
            )
            .fill(LinearGradient(
                colors: [
                    ATHLTHUnifiedDesign.surface,
                    ATHLTHTheme.cardWarm.opacity(compact ? 0.19 : 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: compact ? 17 : ATHLTHUnifiedDesign.radius,
                style: .continuous
            )
            .strokeBorder(ATHLTHUnifiedDesign.outline, lineWidth: 0.8)
        }
        .shadow(
            color: ATHLTHUnifiedDesign.accent.opacity(compact ? 0.025 : 0.045),
            radius: compact ? 7 : 12,
            y: compact ? 3 : 5
        )
    }
}


// Default ATHLTH chrome for secondary screens that would otherwise inherit
// iOS system-gray grouped forms and bright-blue accents. Core Train/Insight
// cards retain their own premium layouts, and semantic metric colors remain.
struct ATHLTHBrandedFormChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(ATHLTHPlanDesign.canvas.ignoresSafeArea())
            .tint(ATHLTHPlanDesign.accentInk)
            .environment(\.defaultMinListRowHeight, 50)
    }
}

extension View {
    func athlthBrandedForm() -> some View {
        modifier(ATHLTHBrandedFormChrome())
    }

    /// For neutral, undecorated secondary cards. Keeps the same corner
    /// radius and hairline gold/stone border as Plan and Train.
    func athlthBrandedCard(
        radius: CGFloat = ATHLTHPlanDesign.cardRadius
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        ATHLTHTheme.card,
                        ATHLTHTheme.cardWarm.opacity(0.56)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(ATHLTHTheme.premiumGold.opacity(0.17), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(
            color: ATHLTHPlanDesign.accentInk.opacity(0.045),
            radius: 11, y: 4
        )
    }
}
