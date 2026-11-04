import SwiftUI

/// An inline day-plan editor. Its draft stays in the day card and nothing is
/// committed to the plan until all required exercise data is available.
struct ATHLTHPlanInlineGroupComposer: View {
    let groupKind: WorkoutBlockGroupKind
    let onInsert: ([WorkoutTemplateBlock], WorkoutKind) -> Void
    let onCancel: () -> Void

    @State private var rounds = 4
    @State private var workSeconds = 60
    @State private var recoverySeconds = 60
    @State private var includeFinalRecovery = false
    @State private var exerciseSlots: [WorkoutTemplateBlock?] = [nil, nil]
    @State private var selectedSlot = 0
    @State private var showingExercisePicker = false

    private let gold = ATHLTHTrainDesign.bronze
    private let ink = ATHLTHTrainDesign.ink
    private let canvas = ATHLTHTrainDesign.canvas

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }

    private var isSuperset: Bool { groupKind == .superset }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: groupKind.symbol)
                    .foregroundStyle(gold)
                    .frame(width: 38, height: 38)
                    .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isSuperset ? "Supersett" : tr("Intervals", "Intervall"))
                        .font(.headline)
                        .foregroundStyle(ink)
                    Text(isSuperset
                         ? tr("Choose two exercises from the library.",
                              "Velg to øvelser fra biblioteket.")
                         : tr("Set efforts and recoveries for this date.",
                              "Sett opp drag og pauser for denne dagen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundStyle(ink)
                        .frame(width: 36, height: 36)
                        .background(canvas, in: Circle())
                }
                .accessibilityLabel(tr("Cancel group", "Avbryt gruppe"))
            }

            if isSuperset {
                ForEach(0..<2, id: \.self) { index in
                    Button {
                        selectedSlot = index
                        showingExercisePicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "dumbbell")
                                .foregroundStyle(gold)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("Exercise", "Øvelse") + " \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(exerciseSlots[index]?.title ??
                                    tr("Choose an exercise", "Velg øvelse"))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: exerciseSlots[index] == nil
                                  ? "plus.circle" : "arrow.left.arrow.right")
                                .foregroundStyle(gold)
                        }
                        .frame(minHeight: 48)
                        .padding(.horizontal, 12)
                        .background(canvas, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Stepper(
                    tr("Effort", "Drag") + ": \(workSeconds) " + tr("sec", "sek"),
                    value: $workSeconds, in: 15...900, step: 15
                )
                Stepper(
                    tr("Recovery", "Pause") + ": \(recoverySeconds) " + tr("sec", "sek"),
                    value: $recoverySeconds, in: 15...600, step: 15
                )
                Toggle(
                    tr("Recovery after final effort", "Pause etter siste drag"),
                    isOn: $includeFinalRecovery
                )
                .tint(gold)
            }

            Stepper(tr("Rounds", "Antall runder") + ": \(rounds)",
                    value: $rounds, in: 1...20)
                .font(.subheadline)
                .tint(gold)

            HStack(spacing: 10) {
                Button {
                    let blocks: [WorkoutTemplateBlock]
                    let workoutKind: WorkoutKind
                    if isSuperset {
                        guard let first = exerciseSlots[0],
                              let second = exerciseSlots[1] else { return }
                        blocks = ATHLTHPlanInlineGroupFactory.superset(
                            first: first, second: second,
                            rounds: rounds, restSeconds: recoverySeconds
                        )
                        workoutKind = .strength
                    } else {
                        blocks = ATHLTHPlanInlineGroupFactory.intervals(
                            rounds: rounds, workSeconds: workSeconds,
                            recoverySeconds: recoverySeconds,
                            includeFinalRecovery: includeFinalRecovery
                        )
                        workoutKind = .running
                    }
                    onInsert(blocks, workoutKind)
                } label: {
                    Label(tr("Add to this day", "Legg til på dagen"),
                          systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 47)
                        .background(gold.gradient,
                                    in: RoundedRectangle(cornerRadius: 13))
                }
                .disabled(isSuperset && exerciseSlots.contains(where: { $0 == nil }))
                .opacity(isSuperset && exerciseSlots.contains(where: { $0 == nil })
                         ? 0.48 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(ATHLTHTrainDesign.rule.opacity(0.55), lineWidth: 1)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ATHLTHAdvancedPlanAddContentView(
                initialKind: .exercise, phase: .main,
                onExercise: { blocks in
                    if let chosen = blocks.first(where: { $0.kind == .exercise }),
                       exerciseSlots.indices.contains(selectedSlot) {
                        exerciseSlots[selectedSlot] = chosen
                        if selectedSlot == 0 {
                            rounds = min(max(chosen.setCount ?? 3, 1), 20)
                        }
                    }
                    showingExercisePicker = false
                },
                onWorkout: { _ in }
            )
        }
    }
}

/// Creates valid, executable workout groups. Incomplete supersets are kept
/// only in transient UI state and can never be persisted as fake exercises.
enum ATHLTHPlanInlineGroupFactory {
    static func intervals(
        rounds: Int, workSeconds: Int, recoverySeconds: Int,
        includeFinalRecovery: Bool
    ) -> [WorkoutTemplateBlock] {
        guard (1...20).contains(rounds),
              workSeconds > 0, recoverySeconds > 0 else { return [] }
        let id = UUID()
        var result: [WorkoutTemplateBlock] = []
        for index in 1...rounds {
            var effort = WorkoutTemplateBlock(
                sequence: result.count + 1, kind: .run,
                title: ATHLTHLocalization.choose(
                    english: "Effort \(index)", norwegian: "Drag \(index)"
                ), exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: Double(workSeconds),
                targetWeightKilograms: nil, loadNote: nil, notes: nil, phase: .main
            )
            effort.cardioActivity = .running
            effort.groupID = id
            effort.groupKind = .intervals
            effort.groupRounds = 1
            result.append(effort)

            if index < rounds || includeFinalRecovery {
                var rest = WorkoutTemplateBlock(
                    sequence: result.count + 1, kind: .rest,
                    title: ATHLTHLocalization.choose(
                        english: "Recovery \(index)", norwegian: "Pause \(index)"
                    ), exerciseSlug: nil, distanceMeters: nil,
                    repetitions: nil, durationSeconds: Double(recoverySeconds),
                    targetWeightKilograms: nil, loadNote: nil,
                    notes: nil, phase: .main
                )
                rest.groupID = id
                rest.groupKind = .intervals
                rest.groupRounds = 1
                result.append(rest)
            }
        }
        return result
    }

    static func superset(
        first: WorkoutTemplateBlock,
        second: WorkoutTemplateBlock,
        rounds: Int, restSeconds: Int
    ) -> [WorkoutTemplateBlock] {
        guard first.kind == .exercise, second.kind == .exercise,
              (1...20).contains(rounds), restSeconds >= 0 else { return [] }
        let id = UUID()
        var members = [first, second].enumerated().map { index, source -> WorkoutTemplateBlock in
            var block = ATHLTHWorkoutPhasePlacement.renumbered(
                source, sequence: index + 1
            )
            block.editorDragID = UUID()
            block.phase = .main
            // Superset rounds, not each exercise's independent set count,
            // define repetition during iPhone/Watch execution.
            block.setCount = nil
            block.restBetweenSetsSeconds = nil
            block.groupID = id
            block.groupKind = .superset
            block.groupRounds = rounds
            return block
        }
        if restSeconds > 0 && rounds > 1 {
            var pause = WorkoutTemplateBlock(
                sequence: 3, kind: .rest,
                title: ATHLTHLocalization.choose(
                    english: "Between rounds", norwegian: "Mellom runder"
                ), exerciseSlug: nil, distanceMeters: nil,
                repetitions: nil, durationSeconds: Double(restSeconds),
                targetWeightKilograms: nil, loadNote: nil,
                notes: nil, phase: .main
            )
            pause.groupID = id
            pause.groupKind = .superset
            pause.groupRounds = rounds
            members.append(pause)
        }
        return members
    }
}
