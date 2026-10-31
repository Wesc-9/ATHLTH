import SwiftUI

/// Small, low-contrast plan mode selector, with full-sized hit areas.
struct ATHLTHPlannerModeSwitch: View {
    @Binding var advanced: Bool

    var body: some View {
        HStack(spacing: 2) {
            option(
                ATHLTHLocalization.choose(english: "Simple", norwegian: "Enkel"),
                selected: !advanced
            ) { advanced = false }
            option(
                ATHLTHLocalization.choose(english: "Advanced", norwegian: "Avansert"),
                selected: advanced
            ) { advanced = true }
        }
        .padding(3)
        .frame(width: 148, height: 34)
        .background(ATHLTHPlanDesign.canvas, in: Capsule())
        .overlay(Capsule().strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.65))
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ATHLTHLocalization.choose(
            english: "Workout editor mode", norwegian: "Visning av øktbygger"
        ))
    }

    private func option(
        _ label: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(ATHLTHTrainDesign.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule()
                            .fill(ATHLTHPlanDesign.selectedSurface)
                            .shadow(color: ATHLTHTrainDesign.ink.opacity(0.08),
                                    radius: 2, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
