import SwiftUI

/// Optional first-use target, never a modification of a published workout.
/// All other prescription data (time, rounds, recoveries, names) stays intact.
enum ATHLTHWorkoutQuickTarget: Equatable {
    case none
    case pace(secondsPerKilometer: Int)
    case heartRateZone(Int)
}

enum ATHLTHWorkoutGoalSheetDecision {
    case continueWith(ATHLTHWorkoutQuickTarget)
    case advanced
    case cancel
}

/// One personalization policy for both the curated catalogue and running
/// library. Only MAIN work receives the athlete's new quick target.
enum ATHLTHWorkoutQuickGoalApplier {
    static func apply(
        _ goal: ATHLTHWorkoutQuickTarget,
        to blocks: [WorkoutTemplateBlock]
    ) -> [WorkoutTemplateBlock] {
        blocks.map { source in
            var block = source
            guard block.kind == .run,
                  block.resolvedPhase == .main else { return block }
            switch goal {
            case .none:
                break
            case .pace(let seconds):
                guard (120...959).contains(seconds) else { return block }
                block.targetPaceSecondsPerKilometer = Double(seconds)
                block.targetHeartRateZone = nil
                block.sourceIntensityZoneLabel = nil
                block.targetHeartRatePercentMin = nil
                block.targetHeartRatePercentMax = nil
            case .heartRateZone(let zone):
                guard (1...5).contains(zone) else { return block }
                block.targetHeartRateZone = zone
                block.targetPaceSecondsPerKilometer = nil
                block.sourceIntensityZoneLabel = nil
                block.targetHeartRatePercentMin = nil
                block.targetHeartRatePercentMax = nil
            }
            return block
        }
    }

    static func apply(
        _ goal: ATHLTHWorkoutQuickTarget,
        to workout: RunningWorkoutTemplate
    ) -> RunningWorkoutTemplate {
        var result = workout
        guard goal != .none else { return result }
        result.blocks = workout.blocks.map { source in
            var block = source
            guard block.kind == .work else { return block }

            var work = block.work
            configure(&work, goal: goal)
            block.work = work

            // Per-repetition targets otherwise override the group target.
            block.repetitionOverrides = block.repetitionOverrides?.map { original in
                var repetition = original
                if var specificWork = repetition.work {
                    configure(&specificWork, goal: goal)
                    repetition.work = specificWork
                }
                return repetition
            }
            return block
        }
        return result
    }

    private static func configure(
        _ step: inout RunningStepTarget,
        goal: ATHLTHWorkoutQuickTarget
    ) {
        switch goal {
        case .none:
            return
        case .pace(let seconds):
            guard (120...959).contains(seconds) else { return }
            step.intensity.kind = .pace
            step.intensity.paceMinSecondsPerKilometer = Double(seconds)
            step.intensity.paceMaxSecondsPerKilometer = Double(seconds)
            step.intensity.heartRateZone = nil
        case .heartRateZone(let zone):
            guard (1...5).contains(zone) else { return }
            step.intensity.kind = .heartRateZone
            step.intensity.heartRateZone = zone
            step.intensity.paceMinSecondsPerKilometer = nil
            step.intensity.paceMaxSecondsPerKilometer = nil
        }
    }
}

/// Compact, branded replacement for the native confirmationDialog.
/// Shared by Plan, Quick Train's catalog preview and My Workouts.
struct ATHLTHWorkoutQuickTargetSheet: View {
    let workoutName: String
    let isRunning: Bool
    let durationMinutes: Int?
    let partCount: Int
    let savingToLibrary: Bool
    let onDecision: (ATHLTHWorkoutGoalSheetDecision) -> Void

    @State private var selectedKind: GoalKind = .none
    @State private var paceMinutes = 5
    @State private var paceSeconds = 0
    @State private var heartRateZone = 3

    private enum GoalKind: String, CaseIterable, Identifiable {
        case none, pace, heartRateZone
        var id: String { rawValue }
    }

    private var tint: Color { ATHLTHPlanDesign.accentInk }
    private var currentGoal: ATHLTHWorkoutQuickTarget {
        switch selectedKind {
        case .none: return .none
        case .pace:
            return .pace(secondsPerKilometer: paceMinutes * 60 + paceSeconds)
        case .heartRateZone: return .heartRateZone(heartRateZone)
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identity

                    VStack(alignment: .leading, spacing: 11) {
                        Text(tr("PERSONAL TARGET", "PERSONLIG MÅL"))
                            .font(.caption2.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(tint)

                        Text(isRunning
                            ? tr(
                                "Choose a target for the work sections, or keep the workout open.",
                                "Velg et mål for arbeidsdelene, eller behold økten uten personlig mål."
                            )
                            : tr(
                                "You can add personal weight, repetitions and rest in Advanced, or continue without targets.",
                                "Du kan legge inn vekt, repetisjoner og pauser i Avansert, eller fortsette uten mål."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if isRunning {
                            HStack(spacing: 8) {
                                goalChip(
                                    tr("No target", "Uten mål"),
                                    symbol: "circle.dashed",
                                    kind: .none
                                )
                                goalChip(
                                    tr("Target pace", "Målfart"),
                                    symbol: "speedometer",
                                    kind: .pace
                                )
                                goalChip(
                                    tr("HR zone", "Pulssone"),
                                    symbol: "heart",
                                    kind: .heartRateZone
                                )
                            }
                            .accessibilityIdentifier("athlth-quick-goal-choices")

                            if selectedKind == .pace {
                                paceControls
                            } else if selectedKind == .heartRateZone {
                                zoneControls
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.white.opacity(0.91),
                        in: RoundedRectangle(cornerRadius: 21)
                    )

                    Label(
                        tr(
                            "Your choices only apply to your copy. The original workout and its recovery times stay unchanged.",
                            "Valgene gjelder bare din kopi. Originaløkten og pausene forblir uendret."
                        ),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                    VStack(spacing: 10) {
                        Button {
                            onDecision(.continueWith(currentGoal))
                        } label: {
                            Label(
                                savingToLibrary
                                    ? tr("Save workout", "Lagre økt")
                                    : tr("Add workout", "Legg til økt"),
                                systemImage: "checkmark"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tint)
                        .accessibilityIdentifier("athlth-quick-goal-continue")

                        Button {
                            onDecision(.advanced)
                        } label: {
                            Label(
                                tr("Customize in Advanced", "Tilpass i Avansert"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint)
                        .accessibilityIdentifier("athlth-quick-goal-advanced")
                    }
                }
                .padding(.horizontal, 19)
                .padding(.vertical, 20)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHPlanDesign.warmCanvas.ignoresSafeArea())
            .navigationTitle(tr("Make it yours", "Tilpass økten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) {
                        onDecision(.cancel)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("athlth-quick-goal-sheet")
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: isRunning ? "figure.run" : "figure.strengthtraining.traditional")
                .font(.title2.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(
                    ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(workoutName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                HStack(spacing: 11) {
                    if let durationMinutes, durationMinutes > 0 {
                        Label("~\(durationMinutes) min", systemImage: "clock")
                    }
                    if partCount > 0 {
                        Label(
                            tr("\(partCount) parts", "\(partCount) deler"),
                            systemImage: "square.stack"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    ATHLTHPlanDesign.selectedSurface.opacity(0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 21)
        )
    }

    private func goalChip(
        _ title: String,
        symbol: String,
        kind: GoalKind
    ) -> some View {
        let selected = selectedKind == kind
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedKind = kind
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.medium))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : ATHLTHPlanDesign.ink)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                selected ? tint : ATHLTHPlanDesign.selectedSurface,
                in: RoundedRectangle(cornerRadius: 13)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var paceControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(tr("Target pace", "Målfart"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%d:%02d min/km", paceMinutes, paceSeconds))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            HStack(spacing: 12) {
                Stepper(
                    tr("Minutes: \(paceMinutes)", "Minutter: \(paceMinutes)"),
                    value: $paceMinutes,
                    in: 2...15
                )
                .font(.subheadline)
            }
            Stepper(
                tr("Seconds: \(paceSeconds)", "Sekunder: \(paceSeconds)"),
                value: $paceSeconds,
                in: 0...55,
                step: 5
            )
            .font(.subheadline)

            Text(
                (3_600.0 / Double(paceMinutes * 60 + paceSeconds))
                    .formatted(.number.precision(.fractionLength(1))) +
                (ATHLTHLocalization.isNorwegian ? " km/t" : " km/h")
            )
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(13)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }

    private var zoneControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Target heart-rate zone", "Målpulssone"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("S\(heartRateZone)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(tint)
            }
            Picker(tr("Zone", "Sone"), selection: $heartRateZone) {
                ForEach(1...5, id: \.self) { zone in
                    Text("S\(zone)").tag(zone)
                }
            }
            .pickerStyle(.segmented)
            Text(tr(
                "Zone follows your ATHLTH heart-rate settings.",
                "Pulssonen bruker pulsinnstillingene dine i ATHLTH."
            ))
            .font(.caption)
            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .padding(13)
        .background(
            ATHLTHPlanDesign.selectedSurface.opacity(0.7),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}
