import SwiftUI

/// One run/walk activity editor backed by the existing WorkoutTemplateBlock.
/// Reused for planned workouts and saved structured workouts.
struct ATHLTHPlannedRunStepEditor: View {
    @Binding var block: WorkoutTemplateBlock
    var routeDistanceMeters: Double? = nil
    @State private var showSourceTargets = false

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
                guard routeDistanceMeters == nil else { return }
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

    static func readOnlyRouteDistance(_ meters: Double) -> String {
        guard meters.isFinite, meters > 0 else { return "–" }
        if meters >= 1_000 {
            return (meters / 1_000).formatted(
                .number.precision(.fractionLength(0...2))
            ) + " km"
        }
        return meters.formatted(
            .number.precision(.fractionLength(0))
        ) + " m"
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
                if let routeDistanceMeters {
                    HStack(spacing: 12) {
                        Text(tr("Distance", "Distanse"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Self.readOnlyRouteDistance(routeDistanceMeters))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(tr("Route distance", "Rutedistanse") +
                                ": " + Self.readOnlyRouteDistance(routeDistanceMeters))
                    }
                    .frame(minHeight: 44)
                } else {
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
                    ATHLTHPlannedPaceTargetView(
                        targetPaceSecondsPerKilometer: $block.targetPaceSecondsPerKilometer,
                        prefersSpeed: block.isIndoor == true,
                        defaultPace: 330,
                        treadmillDisplay: block.isIndoor == true
                    )
                }
            }
            .padding(13)
            .background(ATHLTHPlanDesign.selectedSurface.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 16))

            DisclosureGroup(
                tr("Additional workout targets", "Flere mål fra treningsøkten"),
                isExpanded: $showSourceTargets
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(tr("VMA (% of VMA)", "VMA (% av VMA)"))
                        Spacer()
                        TextField("—", value: $block.targetVMAPercent, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(tr("Elevation (m)", "Høydemeter (m)"))
                        Spacer()
                        TextField("—", value: $block.targetElevationGainMeters, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text(tr("Outdoor gradient (%)", "Stigning ute (%)"))
                        Spacer()
                        TextField("—", value: $block.targetGradientPercent, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField(
                        tr("Source intensity", "Intensitetstype"),
                        text: Binding(
                            get: { block.targetIntensityType ?? "" },
                            set: { block.targetIntensityType = $0.isEmpty ? nil : $0 }
                        )
                    )
                    TextField(
                        tr("Terrain", "Terreng"),
                        text: Binding(
                            get: { block.targetTerrainType ?? "" },
                            set: { block.targetTerrainType = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
                .font(.subheadline)
                .padding(.top, 11)
            }
            .padding(13)
            .background(ATHLTHPlanDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("athlth-running-step-structured-source-targets")
        }
    }
}
