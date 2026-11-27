import SwiftUI

private func planText(_ en: String, _ no: String) -> String {
    ATHLTHLocalization.choose(english: en, norwegian: no)
}

struct ATHLTHCoachChatPlanIntakeCard: View {
    let intake: ATHLTHCoachChatPlanIntake
    let onChange: (ATHLTHCoachChatPlanIntake) -> Void
    let onGenerate: (ATHLTHCoachChatPlanIntake) -> Void

    private func binding<Value>(_ key: WritableKeyPath<ATHLTHCoachChatPlanIntake, Value>) -> Binding<Value> {
        Binding(get: { intake[keyPath: key] }, set: { value in
            var updated = intake
            updated[keyPath: key] = value
            onChange(updated)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(planText("Your plan", "Din treningsplan"), systemImage: "calendar.badge.plus").font(.headline)
            Text(planText("Review the suggested values.", "Kontroller forslagene før Coach lager planen."))
                .font(.caption).foregroundStyle(.secondary)
            Picker(planText("Goal", "Mål"), selection: binding(\.goal)) {
                ForEach(ATHLTHCoachChatPlanIntake.Goal.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            DatePicker(planText("Start date", "Startdato"), selection: binding(\.startDate), displayedComponents: .date)
            Stepper(planText("Weeks", "Uker") + ": \(intake.weeks)", value: binding(\.weeks), in: 2...12)
            Stepper(planText("Workouts per week", "Økter per uke") + ": \(intake.sessionsPerWeek)", value: binding(\.sessionsPerWeek), in: 2...4)
            Picker(planText("Training place", "Treningssted"), selection: binding(\.place)) {
                ForEach(ATHLTHCoachChatPlanIntake.Place.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker(planText("Experience", "Erfaring"), selection: binding(\.experience)) {
                ForEach(ATHLTHCoachChatPlanIntake.Experience.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if intake.submitted {
                Label(planText("Draft created", "Utkast opprettet"), systemImage: "checkmark.circle").font(.subheadline)
            } else {
                Button { onGenerate(intake) } label: {
                    Text(planText("Create plan", "Lag treningsplan")).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze)
                .disabled(!intake.isValid || intake.startDate < Calendar.current.startOfDay(for: Date()))
            }
        }
        .disabled(intake.submitted)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ATHLTHCoachChatPlanCard: View {
    let draft: ATHLTHCoachChatPlanDraft
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar").font(.title2).foregroundStyle(ATHLTHTrainDesign.bronze)
                .frame(width: 42, height: 42)
                .background(ATHLTHTrainDesign.paleGold, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(draft.used ? planText("PLAN ADDED", "PLAN TATT I BRUK") : planText("PLAN DRAFT", "PLANUTKAST"))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(draft.program.title).font(.headline)
                Text(draft.program.summary).font(.caption).foregroundStyle(.secondary)
                Text(planText("Open plan", "Åpne plan")).font(.subheadline.weight(.medium)).foregroundStyle(ATHLTHTrainDesign.bronze)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(ATHLTHTrainDesign.bronze)
        }
        .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ATHLTHCoachChatPlanPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var exerciseLibrary: ExerciseLibraryStore
    let draft: ATHLTHCoachChatPlanDraft
    let ownerID: UUID
    let onUsed: () -> Void
    @State private var week = 1
    @State private var error: String?
    @State private var saving = false
    @State private var confirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(draft.program.title).font(.system(.largeTitle, design: .serif))
                    Text(draft.program.summary).foregroundStyle(.secondary)
                    Label(draft.intake.startDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    HStack {
                        Button { week = max(1, week - 1) } label: { Image(systemName: "chevron.left") }.disabled(week == 1)
                        Spacer()
                        Text(planText("Week", "Uke") + " \(week) / \(draft.program.weeks.count)").font(.headline)
                        Spacer()
                        Button { week = min(draft.program.weeks.count, week + 1) } label: { Image(systemName: "chevron.right") }.disabled(week == draft.program.weeks.count)
                    }
                    if let selected = draft.program.weeks.first(where: { $0.weekNumber == week }) {
                        ForEach(selected.days, id: \.dayIndex) { day in
                            dayView(day)
                        }
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    Text(planText("Review the plan and adapt exercise and intensity to your ability.", "Gjennomgå planen og tilpass øvelser og intensitet til ditt nivå."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button { confirm = true } label: {
                        Text(draft.used ? planText("Already added", "Allerede tatt i bruk") : planText("Use this plan", "Ta planen i bruk"))
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(ATHLTHTrainDesign.bronze).disabled(draft.used || saving)
                }
                .padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(ATHLTHTrainDesign.canvas)
            .navigationTitle(planText("Plan draft", "Planutkast"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(planText("Close", "Lukk")) { dismiss() } } }
            .confirmationDialog(planText("Add this plan to your calendar?", "Legge planen til i treningskalenderen?"), isPresented: $confirm, titleVisibility: .visible) {
                Button(planText("Use plan", "Ta i bruk")) { apply() }
            }
        }
    }

    private func dayView(_ day: AIProgramDraftDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.title).font(.headline)
            if day.sessions.isEmpty { Text(planText("Rest day", "Hviledag")).font(.caption).foregroundStyle(.secondary) }
            ForEach(day.sessions.indices, id: \.self) { index in
                let workout = day.sessions[index]
                DisclosureGroup {
                    if let authored = workout.authoredWorkout {
                        ForEach(Array(authored.resolvedWorkoutBlocks.enumerated()), id: \.offset) { item in
                            HStack(alignment: .top) {
                                Text(item.element.title)
                                Spacer()
                                if let sets = item.element.setCount, let reps = item.element.repetitions {
                                    Text("\(sets) × \(reps)").foregroundStyle(.secondary)
                                }
                            }.font(.subheadline)
                        }
                    }
                    if let notes = workout.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(workout.title).font(.subheadline.weight(.semibold))
                        if let minutes = workout.durationMinutes { Text("\(minutes) min").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    @MainActor private func apply() {
        guard !draft.used, !saving, session.signedIn, session.profile.userID == ownerID else { return }
        saving = true
        defer { saving = false }
        guard draft.intake.startDate >= Calendar.current.startOfDay(for: Date()),
              ATHLTHPlanDraftValidator.issues(in: draft.program, expectedWeeks: draft.intake.weeks,
                maximumSessionsPerWeek: draft.intake.sessionsPerWeek, requireFullWeeks: true,
                requireExecutableWorkouts: true).isEmpty else {
            error = planText("The draft is outdated or invalid. Create a new one in chat.", "Utkastet er utløpt eller ugyldig. Lag et nytt i chatten.")
            return
        }
        var plan = draft.program.makeTrainingPlan(ownerID: ownerID, startDate: draft.intake.startDate,
            exerciseLibrary: exerciseLibrary.allExercises)
        let binding = ATHLTHWorkoutExerciseBinding.bind(&plan, library: exerciseLibrary.allExercises)
        guard binding.isReady else {
            error = planText("Unresolved library exercises: ", "Øvelser som må kobles til biblioteket: ") + binding.unresolved.prefix(6).joined(separator: ", ")
            return
        }
        guard session.addTrainingPlan(plan, saveToLibrary: true) else {
            error = planText("The plan could not be added. Check overlapping plans.", "Planen kunne ikke legges til. Kontroller overlappende planer.")
            return
        }
        onUsed()
        dismiss()
    }
}
