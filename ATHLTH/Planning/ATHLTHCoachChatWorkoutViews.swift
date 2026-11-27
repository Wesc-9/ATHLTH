import SwiftUI

private func workoutText(_ en: String, _ no: String) -> String {
    ATHLTHLocalization.choose(english: en, norwegian: no)
}

struct ATHLTHCoachChatWorkoutIntakeCard: View {
    let intake: ATHLTHCoachChatWorkoutIntake
    let onChange: (ATHLTHCoachChatWorkoutIntake) -> Void
    let onGenerate: (ATHLTHCoachChatWorkoutIntake) -> Void
    private func binding<T>(_ key: WritableKeyPath<ATHLTHCoachChatWorkoutIntake, T>) -> Binding<T> {
        Binding(get: { intake[keyPath: key] }, set: { value in
            var updated = intake
            updated[keyPath: key] = value
            onChange(updated)
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(workoutText("Workout setup", "Sett opp økt"), systemImage: "dumbbell").font(.headline)
            Picker(workoutText("Focus", "Fokus"), selection: binding(\.focus)) {
                ForEach(ATHLTHCoachChatWorkoutIntake.Focus.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            DatePicker(workoutText("Date", "Dato"), selection: binding(\.date), in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
            Stepper(workoutText("Duration", "Varighet") + ": \(intake.minutes) min", value: binding(\.minutes), in: 15...60, step: 5)
            Stepper(workoutText("Alternatives", "Alternativer") + ": \(intake.alternatives)", value: binding(\.alternatives), in: 1...3)
            Picker(workoutText("Place", "Treningssted"), selection: binding(\.place)) {
                ForEach([ATHLTHCoachChatPlanIntake.Place.gym, .home, .outdoors], id: \.self) { Text($0.title).tag($0) }
            }
            Picker(workoutText("Experience", "Erfaring"), selection: binding(\.experience)) {
                ForEach(ATHLTHCoachChatPlanIntake.Experience.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle(workoutText("Only my exercises", "Kun mine øvelser"), isOn: binding(\.ownOnly))
            Text(workoutText("Only available library exercises. Nothing is scheduled yet.", "Kun tilgjengelige bibliotekøvelser. Ingenting planlegges ennå."))
                .font(.caption).foregroundStyle(.secondary)
            Button { onGenerate(intake) } label: {
                Text(workoutText("Submit", "Send inn skjema")).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ATHLTHCoachChatWorkoutCard: View {
    let draft: ATHLTHCoachChatWorkoutDraft
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: draft.workout.kind.systemImage).font(.title2).foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 42, height: 42)
                .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.used ? workoutText("SCHEDULED", "PLANLAGT") : workoutText("WORKOUT DRAFT", "ØKTFORSLAG"))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(draft.workout.title).font(.headline)
                Text("\(draft.workout.durationMinutes ?? 0) min · " + draft.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
                Text(workoutText("Open workout", "Åpne økt")).font(.subheadline).foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTrainDesign.bronze)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ATHLTHCoachChatWorkoutPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    let draft: ATHLTHCoachChatWorkoutDraft
    let ownerID: UUID
    let onUsed: () -> Void
    @State private var date = Date()
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.workout.title).font(.system(.largeTitle, design: .serif))
                    Text("\(draft.workout.durationMinutes ?? 0) min").foregroundStyle(.secondary)
                    ForEach(Array(draft.workout.resolvedWorkoutBlocks.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.element.title).font(.headline)
                            if let sets = item.element.setCount, let reps = item.element.repetitions {
                                Text("\(sets) × \(reps)").font(.subheadline).foregroundStyle(.secondary)
                            } else if let seconds = item.element.durationSeconds {
                                Text("\(Int(seconds / 60)) min").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }
                    DatePicker(workoutText("Date and time", "Dato og klokkeslett"), selection: $date)
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                    Button { apply() } label: {
                        Text(draft.used ? workoutText("Already scheduled", "Allerede planlagt") : workoutText("Schedule workout", "Planlegg økten"))
                            .font(.headline).frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze)
                        .disabled(draft.used || saving)
                }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }.background(ATHLTHTrainDesign.canvas)
            .navigationTitle(workoutText("Workout draft", "Øktforslag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(workoutText("Close", "Lukk")) { dismiss() } } }
            .onAppear {
                date = Calendar.current.isDateInToday(draft.date) ? Date() :
                    Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: draft.date) ?? draft.date
            }
        }
    }

    @MainActor private func apply() {
        guard !draft.used, !saving, session.signedIn, session.profile.userID == ownerID,
              Calendar.current.startOfDay(for: date) >= Calendar.current.startOfDay(for: Date()) else { return }
        saving = true
        defer { saving = false }
        var workout = draft.workout
        let library = exerciseLibrary.selectableExercises
        guard ATHLTHCoachLibraryGate.hasOnlyLibraryReferences(workout, library: library),
              ATHLTHWorkoutExerciseBinding.bind(&workout, library: library).isReady,
              ATHLTHCoachLibraryGate.hasOnlyLibraryReferences(workout, library: library) else {
            error = workoutText("A library exercise is no longer available. Generate a new draft.", "En bibliotekøvelse er ikke lenger tilgjengelig. Lag et nytt forslag.")
            return
        }
        workout.scheduledStart = date
        session.addStandalonePlannedSession(workout)
        onUsed()
        dismiss()
    }
}
