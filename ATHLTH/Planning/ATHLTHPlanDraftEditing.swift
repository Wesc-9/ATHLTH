import SwiftUI

/// Coordinates for editing an AI proposal. The draft is not persisted until
/// the athlete explicitly accepts the final result in AIProgramBuilderView.
struct ATHLTHPlanDraftWorkoutSelection: Identifiable, Equatable {
    let weekNumber: Int
    let dayIndex: Int
    let sessionIndex: Int

    var id: String { "\(weekNumber):\(dayIndex):\(sessionIndex)" }
}

enum ATHLTHPlanDraftEditing {
    static func workout(
        in draft: AIProgramDraft,
        selection: ATHLTHPlanDraftWorkoutSelection
    ) -> AIProgramDraftSession? {
        draft.weeks.first(where: { $0.weekNumber == selection.weekNumber })?
            .days.first(where: { $0.dayIndex == selection.dayIndex })?
            .sessions[safe: selection.sessionIndex]
    }

    static func replacing(
        in draft: AIProgramDraft,
        selection: ATHLTHPlanDraftWorkoutSelection,
        with updated: AIProgramDraftSession
    ) -> AIProgramDraft? {
        guard workout(in: draft, selection: selection) != nil else {
            return nil
        }
        let weeks = draft.weeks.map { week -> AIProgramDraftWeek in
            guard week.weekNumber == selection.weekNumber else { return week }
            let days = week.days.map { day -> AIProgramDraftDay in
                guard day.dayIndex == selection.dayIndex else { return day }
                var sessions = day.sessions
                sessions[selection.sessionIndex] = updated
                return AIProgramDraftDay(
                    dayIndex: day.dayIndex,
                    title: day.title,
                    sessions: sessions
                )
            }
            return AIProgramDraftWeek(
                weekNumber: week.weekNumber,
                title: week.title,
                days: days
            )
        }
        return AIProgramDraft(
            title: draft.title,
            summary: draft.summary,
            weeks: weeks
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The editor changes a copy of the proposal, never active-plan records.
/// A separate "Use program" action is required before any data is saved.
struct ATHLTHPlanDraftWorkoutEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AIProgramDraftSession) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var hasDuration: Bool
    @State private var duration: Int
    @State private var hasDistance: Bool
    @State private var distance: Double
    @State private var hasPace: Bool
    @State private var paceSeconds: Double
    @State private var targets: [ExerciseTarget]
    private let source: AIProgramDraftSession

    private struct ExerciseTarget: Identifiable {
        let id: Int
        let source: AIProgramDraftExercise
        var name: String
        var sets: Int
        var reps: Int
        var hasReps: Bool
        var restSeconds: Int
        var hasRest: Bool
    }

    init(
        workout: AIProgramDraftSession,
        onSave: @escaping (AIProgramDraftSession) -> Void
    ) {
        source = workout
        self.onSave = onSave
        _title = State(initialValue: workout.title)
        _notes = State(initialValue: workout.notes ?? "")
        _hasDuration = State(initialValue: workout.durationMinutes != nil)
        _duration = State(initialValue: workout.durationMinutes ?? 45)
        _hasDistance = State(initialValue: workout.targetDistanceKilometers != nil)
        _distance = State(initialValue: workout.targetDistanceKilometers ?? 5)
        _hasPace = State(initialValue: workout.targetPaceSecondsPerKilometer != nil)
        _paceSeconds = State(initialValue: workout.targetPaceSecondsPerKilometer ?? 360)
        _targets = State(initialValue: workout.exercises.enumerated().map { i, exercise in
            ExerciseTarget(
                id: i, source: exercise, name: exercise.name,
                sets: exercise.sets, reps: exercise.reps ?? 10,
                hasReps: exercise.reps != nil,
                restSeconds: exercise.restSeconds ?? 90,
                hasRest: exercise.restSeconds != nil
            )
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        ATHLTHLocalization.choose(english: "Workout name", norwegian: "Navn på økt"),
                        text: $title
                    )
                    .textInputAutocapitalization(.sentences)
                    TextField(
                        ATHLTHLocalization.choose(english: "Notes (optional)", norwegian: "Notater (valgfritt)"),
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                } header: {
                    Text(ATHLTHLocalization.choose(english: "Workout", norwegian: "Økt"))
                }

                Section {
                    Toggle(
                        ATHLTHLocalization.choose(english: "Planned duration", norwegian: "Planlagt varighet"),
                        isOn: $hasDuration
                    )
                    if hasDuration {
                        Stepper(
                            "\(duration) min",
                            value: $duration, in: 1...360, step: 5
                        )
                    }
                    Toggle(
                        ATHLTHLocalization.choose(english: "Distance target", norwegian: "Distansemål"),
                        isOn: $hasDistance
                    )
                    if hasDistance {
                        Stepper(
                            "\(distance.formatted(.number.precision(.fractionLength(1)))) km",
                            value: $distance, in: 0.5...400, step: 0.5
                        )
                    }
                    Toggle(
                        ATHLTHLocalization.choose(english: "Pace target", norwegian: "Fartsmål"),
                        isOn: $hasPace
                    )
                    if hasPace {
                        Stepper(
                            "\(Int(paceSeconds) / 60):\(String(format: "%02d", Int(paceSeconds) % 60)) min/km",
                            value: $paceSeconds, in: 60...1800, step: 5
                        )
                    }
                } header: {
                    Text(ATHLTHLocalization.choose(english: "Targets", norwegian: "Mål"))
                }

                ForEach($targets) { $target in
                    Section {
                        TextField(
                            ATHLTHLocalization.choose(english: "Exercise", norwegian: "Øvelse"),
                            text: $target.name
                        )
                        Stepper(
                            "\(target.sets) " +
                                ATHLTHLocalization.choose(english: "sets", norwegian: "sett"),
                            value: $target.sets, in: 1...30
                        )
                        Toggle(
                            ATHLTHLocalization.choose(english: "Repetition target", norwegian: "Repetisjonsmål"),
                            isOn: $target.hasReps
                        )
                        if target.hasReps {
                            Stepper(
                                "\(target.reps) " +
                                    ATHLTHLocalization.choose(english: "reps", norwegian: "reps"),
                                value: $target.reps, in: 1...1000
                            )
                        }
                        Toggle(
                            ATHLTHLocalization.choose(english: "Rest between sets", norwegian: "Pause mellom sett"),
                            isOn: $target.hasRest
                        )
                        if target.hasRest {
                            Stepper(
                                "\(target.restSeconds) s",
                                value: $target.restSeconds, in: 0...3600, step: 15
                            )
                        }
                    } header: {
                        Text(ATHLTHLocalization.choose(english: "Exercise \(target.id + 1)", norwegian: "Øvelse \(target.id + 1)"))
                    }
                }

                Section {
                    Text(ATHLTHLocalization.choose(
                        english: "Changes stay in the AI draft until you approve the whole program.",
                        norwegian: "Endringene blir i AI-utkastet til du godkjenner hele programmet."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
            }
            .navigationTitle(ATHLTHLocalization.choose(
                english: "Edit proposed workout", norwegian: "Rediger foreslått økt"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ATHLTHLocalization.choose(english: "Cancel", norwegian: "Avbryt")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ATHLTHLocalization.choose(english: "Save draft", norwegian: "Lagre utkast")) {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              targets.contains(where: {
                                  $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              }))
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func save() {
        let exercises = targets.map { target in
            AIProgramDraftExercise(
                name: target.name.trimmingCharacters(in: .whitespacesAndNewlines),
                sets: target.sets,
                reps: target.hasReps ? target.reps : nil,
                targetRPE: target.source.targetRPE,
                restSeconds: target.hasRest ? target.restSeconds : nil,
                notes: target.source.notes
            )
        }
        let updated = AIProgramDraftSession(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: source.kind,
            durationMinutes: hasDuration ? duration : nil,
            targetDistanceKilometers: hasDistance ? distance : nil,
            targetPaceSecondsPerKilometer: hasPace ? paceSeconds : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            exercises: exercises
        )
        onSave(updated)
        dismiss()
    }
}
