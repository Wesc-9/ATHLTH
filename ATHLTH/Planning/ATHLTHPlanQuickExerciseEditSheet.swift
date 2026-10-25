import SwiftUI

/// Compact, reversible edits directly from a day in Train / Plan.
/// Never rewrites recorded sets or the source of a structured workout.
struct ATHLTHPlanQuickExerciseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID
    let workout: PlannedSession

    @State private var exercises: [PlannedExercise]
    @State private var validationMessage: String?

    init(planID: UUID, workout: PlannedSession) {
        self.planID = planID
        self.workout = workout
        _exercises = State(initialValue: workout.exercises)
    }

    private var currentWorkout: PlannedSession? {
        guard let plan = session.trainingPlan(withID: planID) else {
            return nil
        }
        for week in plan.weeks {
            for day in week.days {
                if let current = day.sessions.first(where: {
                    $0.id == workout.id
                }) {
                    return current
                }
            }
        }
        return nil
    }

    private var canSave: Bool {
        guard let current = currentWorkout,
              current.kind == .strength,
              current.resolvedWorkoutBlocks.isEmpty,
              !current.exercises.isEmpty,
              current.exercises == workout.exercises,
              !session.isPlanSessionManuallyCompleted(
                planID: planID, sessionID: workout.id
              )
        else { return false }

        return !strength.workoutHistory.contains {
            $0.plannedSessionID == workout.id && $0.isFinished
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(ATHLTHLocalization.choose(
                            english: "QUICK ADJUSTMENTS",
                            norwegian: "HURTIGJUSTERINGER"
                        ))
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(ATHLTHTheme.accentDeep)

                        Text(workout.title)
                            .font(.system(
                                size: 25, weight: .medium, design: .serif
                            ))
                            .foregroundStyle(ATHLTHTheme.primaryText)

                        Text(ATHLTHLocalization.choose(
                            english: "Adjust sets, repetitions, time and rest without leaving the day's plan. Equipment, targets and group structure remain unchanged.",
                            norwegian: "Juster sett, repetisjoner, tid og pauser direkte fra dagen. Utstyr, belastning og gruppeinndeling beholdes."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(ATHLTHTheme.mutedText)
                    }
                    .padding(.bottom, 3)

                    ForEach($exercises) { $exercise in
                        ATHLTHPlanQuickExerciseRow(exercise: $exercise)
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(ATHLTHTheme.accentDeep)
                    }

                    Button(action: saveChanges) {
                        Text(ATHLTHLocalization.choose(
                            english: "Save changes",
                            norwegian: "Lagre endringer"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                        .background(
                            ATHLTHTheme.accentDeep,
                            in: RoundedRectangle(cornerRadius: 15)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || exercises == workout.exercises)
                    .opacity(canSave && exercises != workout.exercises ? 1 : 0.48)

                    Text(ATHLTHLocalization.choose(
                        english: "The original plan is updated only after Save. Completed workouts and their results can never be changed here.",
                        norwegian: "Planen oppdateres først når du lagrer. Gjennomførte treningsøkter og resultatene deres kan ikke endres her."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
                }
                .padding(18)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(ATHLTHTheme.canvasTop.ignoresSafeArea())
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Quick edit", norwegian: "Hurtigrediger"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(
                        english: "Cancel", norwegian: "Avbryt"
                    )) { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func saveChanges() {
        guard canSave, let current = currentWorkout else {
            validationMessage = ATHLTHLocalization.choose(
                english: "This session changed or is already completed. Open it again to refresh before editing.",
                norwegian: "Økten er endret eller fullført. Åpne den på nytt før du redigerer."
            )
            return
        }

        guard exercises.allSatisfy({
            $0.sets > 0 &&
            ($0.resolvedTargetKind == .reps
                ? ($0.reps ?? 0) > 0
                : ($0.targetDurationSeconds ?? $0.resolvedTargetDurationSeconds ?? 0) >= 15)
        }) else {
            validationMessage = ATHLTHLocalization.choose(
                english: "Every exercise needs a valid positive target.",
                norwegian: "Alle øvelser må ha et gyldig, positivt mål."
            )
            return
        }

        var revised = current
        revised.exercises = exercises
        session.updateSession(revised, inPlan: planID)
        dismiss()
    }
}

private struct ATHLTHPlanQuickExerciseRow: View {
    @Binding var exercise: PlannedExercise

    private var repsBinding: Binding<Int> {
        Binding(
            get: { exercise.reps ?? 8 },
            set: { exercise.reps = $0 }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: {
                exercise.targetDurationSeconds ??
                    exercise.resolvedTargetDurationSeconds ?? 45
            },
            set: { exercise.targetDurationSeconds = $0 }
        )
    }

    private var restBinding: Binding<Int> {
        Binding(
            get: { exercise.restSeconds ?? 90 },
            set: { exercise.restSeconds = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(exercise.embeddedExercise.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.primaryText)
                Spacer(minLength: 4)
                Text(exercise.compactLoadSummary ?? "")
                    .font(.caption2)
                    .foregroundStyle(ATHLTHTheme.mutedText)
            }

            Stepper(
                value: $exercise.sets,
                in: 1...30
            ) {
                rowLabel(
                    ATHLTHLocalization.choose(
                        english: "Sets", norwegian: "Sett"
                    ),
                    value: "\(exercise.sets)"
                )
            }

            if exercise.resolvedTargetKind == .time {
                Stepper(value: durationBinding, in: 15...3_600, step: 5) {
                    rowLabel(
                        ATHLTHLocalization.choose(
                            english: "Time per set", norwegian: "Tid per sett"
                        ),
                        value: "\(durationBinding.wrappedValue) sek"
                    )
                }
            } else {
                Stepper(value: repsBinding, in: 1...100) {
                    rowLabel(
                        ATHLTHLocalization.choose(
                            english: "Repetitions", norwegian: "Repetisjoner"
                        ),
                        value: "\(repsBinding.wrappedValue)"
                    )
                }
            }

            Stepper(value: restBinding, in: 0...600, step: 15) {
                rowLabel(
                    ATHLTHLocalization.choose(
                        english: "Rest", norwegian: "Pause"
                    ),
                    value: "\(restBinding.wrappedValue) sek"
                )
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 21)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21)
                .stroke(ATHLTHTheme.border, lineWidth: 0.75)
        }
    }

    private func rowLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(ATHLTHTheme.mutedText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(ATHLTHTheme.primaryText)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
