import SwiftUI

/// Edits only a user-selected existing session, after an explicit confirmation.
/// Plan workouts stay inside their plan's supported date range.
struct ATHLTHCoachPostponeWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSessionStore
    let onSaved: (String) -> Void

    struct Option: Identifiable {
        let sessionID: UUID
        let planID: UUID?
        let title: String
        let planTitle: String?
        let scheduledDate: Date
        let lastPlanDate: Date?

        var id: String { (planID?.uuidString ?? "standalone") + sessionID.uuidString }
    }

    @State private var selectedID: String?
    @State private var newDate = Calendar.current.startOfDay(for: Date())
    @State private var showingConfirmation = false
    @State private var errorMessage: String?

    private var options: [Option] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var rows: [Option] = session.standalonePlannedSessions.compactMap { workout in
            guard let date = workout.scheduledStart,
                  date >= today else { return nil }
            return Option(sessionID: workout.id, planID: nil,
                          title: workout.title, planTitle: nil,
                          scheduledDate: date, lastPlanDate: nil)
        }
        for plan in session.trainingPlans {
            guard let startDate = plan.startDate,
                  !session.pausedTrainingPlanIDs.contains(plan.id),
                  !session.deactivatedTrainingPlanIDs.contains(plan.id) else { continue }
            let start = calendar.startOfDay(for: startDate)
            let lastDay = session.trainingPlanEndDate(plan)
            for (weekIndex, week) in plan.weeks.enumerated() {
                for day in week.days {
                    guard let fallback = calendar.date(byAdding: .day,
                        value: weekIndex * 7 + max(day.dayIndex - 1, 0), to: start) else { continue }
                    for workout in day.sessions {
                        let date = workout.scheduledStart ?? fallback
                        guard date >= today else { continue }
                        rows.append(Option(sessionID: workout.id, planID: plan.id,
                                           title: workout.title, planTitle: plan.title,
                                           scheduledDate: date, lastPlanDate: lastDay))
                    }
                }
            }
        }
        return rows.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var chosen: Option? {
        options.first(where: { $0.id == selectedID })
    }

    private var isDateValid: Bool {
        guard let chosen else { return false }
        let calendar = Calendar.current
        let next = calendar.startOfDay(for: newDate)
        let old = calendar.startOfDay(for: chosen.scheduledDate)
        return next > old && (chosen.lastPlanDate.map { next <= $0 } ?? true)
    }

    private var conflicts: Int {
        guard let chosen else { return 0 }
        return options.filter {
            $0.id != chosen.id &&
            Calendar.current.isDate($0.scheduledDate, inSameDayAs: newDate)
        }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.isEmpty {
                    ContentUnavailableView(
                        tr("No upcoming workouts", "Ingen kommende økter"),
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(tr(
                            "Add or activate a training plan, or schedule a single workout first.",
                            "Aktiver en treningsplan eller legg inn en enkeltøkt først."
                        ))
                    )
                } else {
                    Section(tr("Choose the workout", "Velg økten")) {
                        Picker(tr("Upcoming workouts", "Kommende økter"), selection: $selectedID) {
                            Text(tr("Select workout", "Velg økt")).tag(Optional<String>.none)
                            ForEach(options) { option in
                                Text(option.title + " · " +
                                     option.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                                    .tag(Optional(option.id))
                            }
                        }
                    }

                    if let chosen {
                        Section(tr("Schedule", "Tidspunkt")) {
                            LabeledContent(tr("Current date", "Dagens dato")) {
                                Text(chosen.scheduledDate.formatted(date: .abbreviated, time: .shortened))
                            }
                            if let planTitle = chosen.planTitle {
                                LabeledContent(tr("Training plan", "Treningsplan")) {
                                    Text(planTitle).lineLimit(2)
                                }
                            }
                            DatePicker(tr("Move to", "Flytt til"),
                                       selection: $newDate,
                                       in: Calendar.current.startOfDay(for: Date())...,
                                       displayedComponents: .date)
                            if let last = chosen.lastPlanDate {
                                Text(tr(
                                    "This plan currently allows dates through ",
                                    "Denne planen går frem til "
                                ) + last.formatted(date: .abbreviated, time: .omitted))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            if conflicts > 0 {
                                Label(tr(
                                    "There are already \(conflicts) other workouts on the selected date.",
                                    "Det ligger allerede \(conflicts) andre økter på valgt dato."),
                                    systemImage: "calendar.badge.exclamationmark")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                            }
                            if !isDateValid {
                                Text(tr(
                                    "Choose a later date within the plan's duration.",
                                    "Velg en senere dato innenfor planens varighet."
                                ))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let errorMessage {
                        Section {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Text(tr(
                            "Nothing moves until you confirm. Your completed workouts are not changed.",
                            "Ingenting flyttes før du bekrefter. Fullførte økter endres ikke."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(tr("Postpone workout", "Utsett en økt"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Cancel", "Avbryt")) { dismiss() }
                }
            }
            .onChange(of: selectedID) { _, _ in
                if let chosen {
                    newDate = Calendar.current.date(byAdding: .day, value: 1,
                                                    to: chosen.scheduledDate) ?? chosen.scheduledDate
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showingConfirmation = true
                } label: {
                    Label(tr("Review move", "Bekreft flytting"), systemImage: "calendar.badge.clock")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(ATHLTHPlanDesign.accentInk)
                .disabled(!isDateValid)
                .padding()
                .background(.regularMaterial)
            }
            .confirmationDialog(
                tr("Move this workout?", "Flytte denne økten?"),
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button(tr("Move workout", "Flytt økten"), action: applyMove)
                Button(tr("Cancel", "Avbryt"), role: .cancel) {}
            } message: {
                if let chosen {
                    Text(chosen.title + ": " +
                         chosen.scheduledDate.formatted(date: .abbreviated, time: .omitted) +
                         " → " + newDate.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func applyMove() {
        guard isDateValid, let chosen else { return }
        let calendar = Calendar.current
        let target = calendar.startOfDay(for: newDate)
        if let planID = chosen.planID {
            guard session.movePlanSession(planID: planID, sessionID: chosen.sessionID,
                                          to: target) else {
                errorMessage = tr("Unable to move this plan workout. No changes were saved.",
                                  "Kunne ikke flytte denne planøkten. Ingenting ble lagret.")
                return
            }
        } else {
            guard var workout = session.standalonePlannedSessions.first(where: {
                $0.id == chosen.sessionID
            }) else {
                errorMessage = tr("This workout is no longer available.",
                                  "Denne økten er ikke lenger tilgjengelig.")
                return
            }
            let time = calendar.dateComponents([.hour, .minute], from: chosen.scheduledDate)
            workout.scheduledStart = calendar.date(
                bySettingHour: time.hour ?? 18, minute: time.minute ?? 0,
                second: 0, of: target
            ) ?? target
            session.updateStandalonePlannedSession(workout)
        }
        onSaved(tr(
            "Moved \(chosen.title) to \(target.formatted(date: .abbreviated, time: .omitted)).",
            "Flyttet \(chosen.title) til \(target.formatted(date: .abbreviated, time: .omitted))."
        ))
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}
