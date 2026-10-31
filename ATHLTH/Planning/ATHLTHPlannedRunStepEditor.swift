import SwiftUI

/// One run/walk activity editor backed by the existing WorkoutTemplateBlock.
/// Reused for planned workouts and saved structured workouts.
struct ATHLTHPlannedRunStepEditor: View {
    @Binding var block: WorkoutTemplateBlock

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var activity: Binding<WorkoutCardioActivity> {
        Binding(
            get: { block.cardioActivity ?? .running },
            set: { value in
                let oldName = block.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let standardNames = [
                    "running", "run", "løping", "walking", "walk", "gåing",
                    "løpeintervall", "run interval", "gåintervall", "walking interval"
                ]
                block.cardioActivity = value
                if standardNames.contains(oldName) {
                    let interval = block.groupKind == .intervals
                    block.title = interval
                        ? (value == .walking
                            ? tr("Walking interval", "Gåintervall")
                            : tr("Running interval", "Løpeintervall"))
                        : (value == .walking
                            ? tr("Walking", "Gåing")
                            : tr("Running", "Løping"))
                }
            }
        )
    }

    private var timed: Binding<Bool> {
        Binding(
            get: { block.durationSeconds != nil },
            set: { value in
                if value {
                    block.durationSeconds = block.durationSeconds ?? 600
                    block.distanceMeters = nil
                } else {
                    block.distanceMeters = block.distanceMeters ?? 1_000
                    block.durationSeconds = nil
                }
            }
        )
    }

    private var indoors: Binding<Bool> {
        Binding(
            get: { block.isIndoor == true },
            set: { value in
                block.isIndoor = value
                if !value { block.treadmillInclinePercent = nil }
            }
        )
    }

    private var treadmill: Binding<Bool> {
        Binding(
            get: { block.treadmillInclinePercent != nil },
            set: { value in
                block.treadmillInclinePercent = value ? (block.treadmillInclinePercent ?? 0) : nil
                if value {
                    block.isIndoor = true
                    block.targetPaceSecondsPerKilometer =
                        block.targetPaceSecondsPerKilometer ?? 360
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Picker(tr("Activity", "Aktivitet"), selection: activity) {
                Text(tr("Run", "Løp")).tag(WorkoutCardioActivity.running)
                Text(tr("Walk", "Gå")).tag(WorkoutCardioActivity.walking)
            }
            .pickerStyle(.segmented)

            TextField(
                tr("Activity (optional)", "Navn på aktivitet (valgfritt)"),
                text: $block.title
            )
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 9) {
                Text(tr("STEP GOAL", "MÅL FOR DELØKTEN"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTrainDesign.bronze)
                Picker(tr("Goal", "Mål"), selection: timed) {
                    Text(tr("Distance", "Distanse")).tag(false)
                    Text(tr("Time", "Tid")).tag(true)
                }
                .pickerStyle(.segmented)
                if block.durationSeconds != nil {
                    ATHLTHPlannedDurationEditor(durationSeconds: $block.durationSeconds)
                } else {
                    Stepper(
                        value: Binding(
                            get: { block.distanceMeters ?? 1_000 },
                            set: { block.distanceMeters = $0 }
                        ),
                        in: 1...100_000, step: 100
                    ) {
                        Text("\(Int(block.distanceMeters ?? 1_000)) m")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                Toggle(tr("Indoor workout", "Innendørs"), isOn: indoors)
                    .tint(ATHLTHTrainDesign.bronze)
                    .font(.subheadline.weight(.medium))
                if block.isIndoor == true {
                    Picker(tr("Indoor type", "Innendørstype"), selection: treadmill) {
                        Text(tr("Indoor running", "Innendørs løping")).tag(false)
                        Text(tr("Treadmill", "Tredemølle")).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                if block.treadmillInclinePercent != nil {
                    ATHLTHPlannedTreadmillTargetsView(block: $block)
                } else {
                    Toggle(tr("Target pace", "Måltempo"),
                           isOn: Binding(
                            get: { block.targetPaceSecondsPerKilometer != nil },
                            set: { block.targetPaceSecondsPerKilometer = $0 ? 330 : nil }
                           ))
                        .tint(ATHLTHTrainDesign.bronze)
                    if block.targetPaceSecondsPerKilometer != nil {
                        Stepper(value: Binding(
                            get: { block.targetPaceSecondsPerKilometer ?? 330 },
                            set: { block.targetPaceSecondsPerKilometer = $0 }
                        ), in: 60...3_600, step: 5) {
                            let pace = Int(block.targetPaceSecondsPerKilometer ?? 330)
                            Text("\(pace / 60):\(String(format: "%02d", pace % 60)) min/km")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
            .padding(13)
            .background(ATHLTHPlanDesign.selectedSurface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
