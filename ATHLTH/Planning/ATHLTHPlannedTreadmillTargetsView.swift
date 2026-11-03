import SwiftUI

/// Treadmill-only planned targets. These do not remotely control a machine.
struct ATHLTHPlannedTreadmillTargetsView: View {
    @Binding var block: WorkoutTemplateBlock
    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(tr("Treadmill settings", "Tredemølleinnstillinger"),
                  systemImage: "figure.run.treadmill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)

            ATHLTHPlannedPaceTargetView(
                targetPaceSecondsPerKilometer: $block.targetPaceSecondsPerKilometer,
                prefersSpeed: true,
                defaultPace: 360
            )
            Stepper(value: Binding(
                get: { block.treadmillInclinePercent ?? 0 },
                set: { block.treadmillInclinePercent = min(max($0, 0), 20) }
            ), in: 0...20, step: 0.5) {
                HStack {
                    Text(tr("Incline", "Stigning"))
                    Spacer()
                    Text((block.treadmillInclinePercent ?? 0).formatted(
                        .number.precision(.fractionLength(1))) + " %")
                        .fontWeight(.semibold)
                }
            }
            Text(tr(
                "These are targets for your workout, not remote controls for the treadmill.",
                "Dette er mål for økten – ikke fjernstyring av tredemøllen."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
