import SwiftUI

/// Treadmill-only planned targets. These do not remotely control a machine.
struct ATHLTHPlannedTreadmillTargetsView: View {
    @Binding var block: WorkoutTemplateBlock
    @State private var showSpeed = true

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var speed: Binding<Double> {
        Binding(
            get: {
                ATHLTHPlannedTreadmillTargets.speed(
                    forPace: block.targetPaceSecondsPerKilometer ?? 360
                )
            },
            set: { value in
                block.targetPaceSecondsPerKilometer =
                    ATHLTHPlannedTreadmillTargets.pace(forSpeed: value)
            }
        )
    }

    private var pace: Binding<Double> {
        Binding(
            get: { block.targetPaceSecondsPerKilometer ?? 360 },
            set: { block.targetPaceSecondsPerKilometer = min(max($0, 144), 3_600) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(tr("Treadmill settings", "Tredemølleinnstillinger"),
                  systemImage: "figure.run.treadmill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ATHLTHTrainDesign.ink)

            Toggle(tr("Target speed", "Målhastighet"), isOn: Binding(
                get: { block.targetPaceSecondsPerKilometer != nil },
                set: { block.targetPaceSecondsPerKilometer = $0 ? 360 : nil }
            ))
            .tint(ATHLTHTrainDesign.bronze)
            if block.targetPaceSecondsPerKilometer != nil {
                Picker(tr("Speed display", "Hastighetsvisning"), selection: $showSpeed) {
                    Text(tr("km/h", "km/t")).tag(true)
                    Text("min/km").tag(false)
                }
                .pickerStyle(.segmented)
                if showSpeed {
                    Stepper(value: speed, in: 1...25, step: 0.1) {
                        HStack {
                            Text(tr("Speed", "Hastighet"))
                            Spacer()
                            Text(speed.wrappedValue.formatted(
                                .number.precision(.fractionLength(1))) + " km/t")
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    Stepper(value: pace, in: 144...3_600, step: 5) {
                        let seconds = Int(pace.wrappedValue)
                        HStack {
                            Text(tr("Pace", "Tempo"))
                            Spacer()
                            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60)) min/km")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
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
