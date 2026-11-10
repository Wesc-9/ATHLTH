import SwiftUI

/// Three independent resizeable Plan Studio columns. Width preferences are
/// deliberately window-local and reset each time the planner is opened.
struct ATHLTHStudioPlanningColumns<Weeks: View, CalendarContent: View, DayEditor: View>: View {
    @State private var weekFraction: CGFloat = 0.19
    @State private var editorFraction: CGFloat = 0.28
    @GestureState private var weeksDrag: CGFloat = 0
    @GestureState private var editorDrag: CGFloat = 0

    let weeks: Weeks
    let calendar: CalendarContent
    let dayEditor: DayEditor

    init(
        @ViewBuilder weeks: () -> Weeks,
        @ViewBuilder calendar: () -> CalendarContent,
        @ViewBuilder dayEditor: () -> DayEditor
    ) {
        self.weeks = weeks()
        self.calendar = calendar()
        self.dayEditor = dayEditor()
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let available = max(0, totalWidth - 28)
            let minWeeks: CGFloat = 160
            let minCalendar: CGFloat = 345
            let minEditor: CGFloat = 265
            let weeksWidth = min(
                max(minWeeks, available - minCalendar - minEditor),
                max(minWeeks, available * weekFraction + weeksDrag)
            )
            let editorWidth = min(
                max(minEditor, available - minCalendar - weeksWidth),
                max(minEditor, available * editorFraction - editorDrag)
            )

            HStack(alignment: .top, spacing: 0) {
                weeks
                    .frame(width: weeksWidth, height: geometry.size.height)
                weeksDivider(width: totalWidth)
                calendar
                    .frame(width: max(0, available - weeksWidth - editorWidth),
                           height: geometry.size.height)
                editorDivider(width: totalWidth)
                dayEditor
                    .frame(width: editorWidth, height: geometry.size.height)
            }
        }
        .onAppear {
            weekFraction = 0.19
            editorFraction = 0.28
        }
        .accessibilityIdentifier("athlth-studio-resizable-planning-columns")
    }

    private var dividerArtwork: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 14)
            .overlay {
                Capsule()
                    .fill(ATHLTHStudioStyle.gold.opacity(0.45))
                    .frame(width: 3, height: 54)
            }
            .contentShape(Rectangle())
    }

    private func weeksDivider(width: CGFloat) -> some View {
        dividerArtwork
            .gesture(DragGesture(minimumDistance: 3)
                .updating($weeksDrag) { gesture, value, _ in
                    value = gesture.translation.width
                }
                .onEnded { gesture in
                    guard width > 0 else { return }
                    weekFraction = min(0.43, max(0.14,
                        weekFraction + gesture.translation.width / width))
                })
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Resize plan weeks column",
                norwegian: "Endre bredden på planuker"
            ))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: weekFraction = min(0.43, weekFraction + 0.04)
                case .decrement: weekFraction = max(0.14, weekFraction - 0.04)
                @unknown default: break
                }
            }
    }

    private func editorDivider(width: CGFloat) -> some View {
        dividerArtwork
            .gesture(DragGesture(minimumDistance: 3)
                .updating($editorDrag) { gesture, value, _ in
                    value = gesture.translation.width
                }
                .onEnded { gesture in
                    guard width > 0 else { return }
                    editorFraction = min(0.46, max(0.20,
                        editorFraction - gesture.translation.width / width))
                })
            .accessibilityLabel(ATHLTHLocalization.choose(
                english: "Resize day editor column",
                norwegian: "Endre bredden på dagredaktøren"
            ))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: editorFraction = min(0.46, editorFraction + 0.04)
                case .decrement: editorFraction = max(0.20, editorFraction - 0.04)
                @unknown default: break
                }
            }
    }
}
