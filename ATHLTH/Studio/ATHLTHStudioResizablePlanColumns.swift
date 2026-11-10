import SwiftUI

/// Adjustable, three-column iPad Planning canvas. Panel widths are intentionally
/// session-only: every new entrance starts at the designed 19 / 53 / 28 split.
struct ATHLTHStudioResizablePlanColumns<Weeks: View, Calendar: View, Editor: View>: View {
    @State private var weeksFraction = 0.19
    @State private var editorFraction = 0.28
    @State private var weeksTranslation: CGFloat = 0
    @State private var editorTranslation: CGFloat = 0

    private let weeks: Weeks
    private let calendar: Calendar
    private let dayEditor: Editor
    private let dividerWidth: CGFloat = 12

    init(
        @ViewBuilder weeks: () -> Weeks,
        @ViewBuilder calendar: () -> Calendar,
        @ViewBuilder dayEditor: () -> Editor
    ) {
        self.weeks = weeks()
        self.calendar = calendar()
        self.dayEditor = dayEditor()
    }

    var body: some View {
        GeometryReader { geometry in
            let available = max(1, geometry.size.width - dividerWidth * 2)
            let left = weeksWidth(available, delta: weeksTranslation)
            let right = editorWidth(available, left: left, delta: editorTranslation)

            HStack(spacing: 0) {
                weeks
                    .frame(width: left)
                    .frame(maxHeight: .infinity)
                    .clipped()

                divider(
                    label: ATHLTHLocalization.choose(
                        english: "Resize plan weeks", norwegian: "Endre bredde på planuker"
                    ),
                    onChanged: { weeksTranslation = $0 },
                    onEnded: { translation in
                        weeksFraction = Double(weeksWidth(available, delta: translation) / available)
                        weeksTranslation = 0
                    },
                    onAdjust: { amount in
                        weeksFraction = Double(weeksWidth(available,
                            delta: CGFloat(amount) * available * 0.04) / available)
                    }
                )

                calendar
                    .frame(width: max(0, available - left - right))
                    .frame(maxHeight: .infinity)
                    .clipped()

                divider(
                    label: ATHLTHLocalization.choose(
                        english: "Resize day editor", norwegian: "Endre bredde på dagsredigering"
                    ),
                    onChanged: { editorTranslation = -$0 },
                    onEnded: { translation in
                        editorFraction = Double(
                            editorWidth(available, left: left, delta: -translation) / available
                        )
                        editorTranslation = 0
                    },
                    onAdjust: { amount in
                        editorFraction = Double(editorWidth(available, left: left,
                            delta: CGFloat(amount) * available * 0.04) / available)
                    }
                )

                dayEditor
                    .frame(width: right)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
        .onAppear {
            weeksFraction = 0.19
            editorFraction = 0.28
            weeksTranslation = 0
            editorTranslation = 0
        }
    }

    private func weeksWidth(_ available: CGFloat, delta: CGFloat) -> CGFloat {
        let minimum: CGFloat = 165
        let maximum = max(minimum, available - 350 - 220)
        return min(maximum, max(minimum, available * weeksFraction + delta))
    }

    private func editorWidth(
        _ available: CGFloat, left: CGFloat, delta: CGFloat
    ) -> CGFloat {
        let minimum: CGFloat = 220
        let maximum = max(minimum, available - left - 350)
        return min(maximum, max(minimum, available * editorFraction + delta))
    }

    private func divider(
        label: String,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat) -> Void,
        onAdjust: @escaping (Double) -> Void
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: dividerWidth)
            .overlay {
                Capsule()
                    .fill(ATHLTHStudioStyle.outline.opacity(0.8))
                    .frame(width: 3, height: 58)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { onChanged($0.translation.width) }
                    .onEnded { onEnded($0.translation.width) }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onAdjust(1)
                case .decrement: onAdjust(-1)
                @unknown default: break
                }
            }
    }
}
