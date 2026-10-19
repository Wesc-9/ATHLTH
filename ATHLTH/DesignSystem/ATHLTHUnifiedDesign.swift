import SwiftUI

/// Consistent high-contrast premium surfaces for secondary ATHLTH screens.
/// Intentionally mirrors ATHLTHCard's zero-spacing layout to preserve the
/// semantics of live metrics and controls already in each screen.
enum ATHLTHUnifiedDesign {
    static let canvas = ATHLTHPlanDesign.canvas
    static let ink = ATHLTHTheme.primaryText
    static let secondary = ATHLTHPlanDesign.secondaryInk
    static let accent = ATHLTHPlanDesign.accent
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
