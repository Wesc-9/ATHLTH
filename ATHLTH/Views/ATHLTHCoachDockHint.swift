import SwiftUI

/// Minimal, grey grab handle above the tab bar for ATHLTH Coach.
/// Its invisible hit target is larger than the visible line for accessibility.
struct ATHLTHCoachDockHint: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Capsule()
                .fill(Color.gray.opacity(0.65))
                .frame(width: 38, height: 4)
                .frame(width: 70, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            english: "Double tap or swipe up to open Coach",
            norwegian: "Dobbelttrykk eller sveip opp for å åpne Coach"
        ))
    }
}
