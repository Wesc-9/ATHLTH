import SwiftUI

/// Reuse saved sessions without touching their original records.
struct ATHLTHTrainSavedWorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore

    let planID: UUID
    let dayID: UUID
    var onInserted: (() -> Void)? = nil

    @State private var search = ""
    @State private var errorMessage: String?

    private let graphite = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let paper = Color(red: 0.984, green: 0.976, blue: 0.963)

    private var results: [PlannedSession] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return session.savedWorkoutTemplates }
        return session.savedWorkoutTemplates.filter {
            $0.title.localizedCaseInsensitiveContains(term)
                || $0.kind.title.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(tr("Your training collection", "Dine lagrede økter"))
                        .font(.system(size: 28, weight: .regular, design: .serif))
                    Text(tr(
                        "Add an independent copy to this day. The original remains unchanged.",
                        "Legg inn en egen kopi på valgt dag. Originalen påvirkes ikke."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if results.isEmpty {
                        ContentUnavailableView(
                            tr("No saved workouts found", "Ingen lagrede økter"),
                            systemImage: "rectangle.stack",
                            description: Text(tr("Save a workout to reuse it here.",
                                                  "Lagre en økt for å bruke den her senere."))
                        )
                    }
                    ForEach(results) { workout in
                        Button {
                            if session.insertSavedWorkoutIntoPlan(
                                templateID: workout.id,
                                planID: planID,
                                dayID: dayID
                            ) {
                                onInserted?()
                                dismiss()
                            } else {
                                errorMessage = tr(
                                    "Could not insert workout. Please try again.",
                                    "Kunne ikke legge inn økten. Prøv igjen."
                                )
                            }
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: workout.kind.systemImage)
                                    .font(.system(size: 19, weight: .light))
                                    .foregroundStyle(bronze)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(workout.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(workout.kind.title + workout.durationMinutes.map {
                                        " · \($0) min"
                                    }.orEmpty)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if !workout.exercises.isEmpty {
                                        Text("\(workout.exercises.count) " + tr("exercises", "øvelser"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                            }
                            .foregroundStyle(graphite)
                            .padding(15)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(paper.ignoresSafeArea())
            .searchable(
                text: $search,
                prompt: tr("Search saved workouts", "Søk i lagrede økter")
            )
            .navigationTitle(tr("Saved workouts", "Lagrede økter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .alert(tr("Unable to insert workout", "Kunne ikke legge til økt"),
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

struct ATHLTHTrainSessionTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let planID: UUID
    let sessionID: UUID
    let copyInsteadOfMove: Bool

    @State private var selectedWeek = 0
    @State private var selectedDayID: UUID?
    @State private var errorMessage: String?

    private let ink = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let bronze = Color(red: 0.65, green: 0.53, blue: 0.37)
    private let paper = Color(red: 0.984, green: 0.976, blue: 0.963)

    private var plan: TrainingPlan? {
        session.trainingPlan(withID: planID)
    }
    private var completed: Bool {
        session.isPlanSessionCompleted(
            planID: planID,
            sessionID: sessionID,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
    }
    private var selectedDate: Date? {
        guard let plan, let start = plan.startDate,
              let week = plan.weeks[safe: selectedWeek],
              let day = week.days.first(where: { $0.id == selectedDayID })
        else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: selectedWeek * 7 + day.dayIndex - 1,
            to: Calendar.current.startOfDay(for: start)
        )
    }
    private var canCommit: Bool {
        guard selectedDayID != nil, let date = selectedDate else { return false }
        if copyInsteadOfMove { return true }
        return !completed && date >= Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(copyInsteadOfMove
                         ? tr("Copy to a new day", "Kopier til ny dag")
                         : tr("Move your workout", "Flytt treningsøkten"))
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                    Text(copyInsteadOfMove
                         ? tr("The source stays in your plan; the copy gets a new ID.",
                              "Originalen beholdes, og kopien får sin egen økt-ID.")
                         : tr("Choose the future day for this planned workout.",
                              "Velg hvilken kommende dag økten skal flyttes til."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let plan {
                        Picker(tr("Week", "Uke"), selection: $selectedWeek) {
                            ForEach(plan.weeks.indices, id: \.self) { index in
                                Text(tr("Week \(index + 1)", "Uke \(index + 1)"))
                                    .tag(index)
                            }
                        }
                        .tint(ink)
                        .onChange(of: selectedWeek) { _, _ in
                            selectedDayID = nil
                        }
                        if let week = plan.weeks[safe: selectedWeek] {
                            ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                                let label = dayDate(day.dayIndex, week: selectedWeek, plan: plan)
                                Button { selectedDayID = day.id } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: selectedDayID == day.id
                                              ? "checkmark.circle.fill"
                                              : "circle")
                                            .foregroundStyle(bronze)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(label.formatted(.dateTime.weekday(.wide).day().month()))
                                                .font(.subheadline.weight(.semibold))
                                            Text("\(day.sessions.count) " + tr("planned sessions", "planlagte økter"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .foregroundStyle(ink)
                                    .padding(14)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if completed && !copyInsteadOfMove {
                        Label(tr("Completed workouts cannot be moved. Copy the workout instead.",
                                 "Gjennomførte økter kan ikke flyttes. Kopier økten i stedet."),
                              systemImage: "checkmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button(action: commit) {
                        HStack {
                            Spacer()
                            Text(copyInsteadOfMove
                                 ? tr("Copy workout", "Kopier økt")
                                 : tr("Move workout", "Flytt økt"))
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(15)
                        .background(ink, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCommit)
                    .opacity(canCommit ? 1 : 0.45)
                }
                .padding(18)
            }
            .background(paper.ignoresSafeArea())
            .navigationTitle(tr("Schedule", "Planlegging"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
            .alert(tr("Unable to update plan", "Kunne ikke endre planen"),
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.light)
    }

    private func commit() {
        guard canCommit, let dayID = selectedDayID else { return }
        let success: Bool
        if copyInsteadOfMove {
            success = session.copyPlanWorkout(
                planID: planID,
                workoutID: sessionID,
                dayID: dayID
            )
        } else if let date = selectedDate {
            success = session.movePlanSession(
                planID: planID,
                sessionID: sessionID,
                to: date
            )
        } else {
            return
        }
        if success {
            dismiss()
        } else {
            errorMessage = tr(
                "The plan has changed. Please select the day again.",
                "Treningsplanen er endret. Velg dagen på nytt."
            )
        }
    }

    private func dayDate(_ dayIndex: Int, week: Int, plan: TrainingPlan) -> Date {
        guard let start = plan.startDate else { return Date() }
        return Calendar.current.date(
            byAdding: .day,
            value: week * 7 + dayIndex - 1,
            to: Calendar.current.startOfDay(for: start)
        ) ?? start
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
