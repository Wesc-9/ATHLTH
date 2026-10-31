import SwiftUI

/// Compact entry to the full ATHLTH Coach conversation, anchored just above
/// the system tab bar. Both tapping and swiping upward open the same screen.
struct ATHLTHCoachDockHint: View {
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(ATHLTHPlanDesign.accentInk.opacity(0.72))
                    .frame(width: 32, height: 3)
                    .accessibilityHidden(true)

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .accessibilityHidden(true)

                    Text(ATHLTHLocalization.choose(
                        english: "Swipe up for Coach",
                        norwegian: "Sveip opp for Coach"
                    ))
                    .font(dynamicTypeSize.isAccessibilitySize
                          ? .subheadline.weight(.semibold)
                          : .caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ATHLTHPlanDesign.accentInk)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        ATHLTHPlanDesign.accentInk.opacity(0.18),
                        lineWidth: 0.8
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.06), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard value.translation.height < -22,
                          abs(value.translation.height) >
                            abs(value.translation.width)
                    else { return }
                    onOpen()
                }
        )
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Open ATHLTH Coach",
            norwegian: "Åpne ATHLTH Coach"
        ))
        .accessibilityHint(ATHLTHLocalization.choose(
            english: "Double tap or swipe upward to start a conversation",
            norwegian: "Dobbelttrykk eller sveip opp for å starte en samtale"
        ))
    }
}
