import SwiftUI

/// Transparent what-if analysis. The selected workout is NOT moved until the
/// athlete explicitly approves and the canonical plan store validates it.
struct ATHLTHStudioPlanningScenarioView: View {
    let planID: UUID
    var onAskCoach: (() -> Void)?
    var onAddWorkout: (() -> Void)?

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedWorkoutID: UUID?
    @State private var targetDayID: UUID?
    @State private var showingApproval = false
    @State private var scenarioAction = "move"
    @State private var lastSkippedID: UUID?
    @State private var errorText: String?

    private struct Candidate: Identifiable {
        let workout: PlannedSession
        let date: Date
        let weekIndex: Int
        let dayID: UUID
        var id: UUID { workout.id }
    }
    private struct Target: Identifiable {
        let id: UUID
        let date: Date
        let weekIndex: Int
        let dayIndex: Int
    }

    private var plan: TrainingPlan? { session.trainingPlan(withID: planID) }

    private var candidates: [Candidate] {
        guard let plan else { return [] }
        return plan.weeks.enumerated().flatMap { index, week in
            week.days.flatMap { day -> [Candidate] in
                guard let date = ATHLTHStudioPlanWeekSummary.date(
                    for: day, inWeekIndex: index, planStart: plan.startDate
                ), Calendar.current.startOfDay(for: date) >=
                    Calendar.current.startOfDay(for: .now)
                else { return [] }
                return day.sessions.filter { workout in
                    !workout.isExplicitRestDay &&
                    !session.isPlanSessionSkipped(
                        planID: plan.id, sessionID: workout.id
                    ) &&
                    !session.isPlanSessionCompleted(
                        planID: plan.id, sessionID: workout.id,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                }.map {
                    Candidate(workout: $0, date: date,
                              weekIndex: index, dayID: day.id)
                }
            }
        }.sorted { $0.date < $1.date }
    }

    private var targets: [Target] {
        guard let plan else { return [] }
        return plan.weeks.enumerated().flatMap { index, week in
            week.days.compactMap { day -> Target? in
                guard let date = ATHLTHStudioPlanWeekSummary.date(
                    for: day, inWeekIndex: index, planStart: plan.startDate
                ), Calendar.current.startOfDay(for: date) >=
                    Calendar.current.startOfDay(for: .now),
                      !day.sessions.contains(where: \.isExplicitRestDay)
                else { return nil }
                return Target(id: day.id, date: date,
                              weekIndex: index, dayIndex: day.dayIndex)
            }
        }.sorted { $0.date < $1.date }
    }

    private var chosen: Candidate? {
        candidates.first(where: { $0.id == selectedWorkoutID }) ?? candidates.first
    }
    private var destination: Target? {
        targets.first(where: { $0.id == targetDayID })
    }
    private var validChange: Bool {
        guard let chosen else { return false }
        if scenarioAction == "skip" { return true }
        guard let destination else { return false }
        return chosen.dayID != destination.id
    }
    private func tr(_ en: String, _ no: String) -> String {
        ATHLTHLocalization.choose(english: en, norwegian: no)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(tr("WHAT-IF PLANNING", "HVA OM-PLANLEGGING"),
                          systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(ATHLTHStudioStyle.gold)
                    Text(tr("Preview before you change the plan",
                            "Se konsekvensene før du endrer planen"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ATHLTHStudioStyle.ink)
                    Text(tr(
                        "This preview uses scheduled duration and activity type. It does not predict fitness, injuries or a medical recovery score.",
                        "Forhåndsvisningen bygger på planlagt varighet og aktivitetstype. Den forutsier ikke formutvikling, skader eller medisinsk restitusjon."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let plan, !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker(tr("Planned workout", "Planlagt økt"),
                                   selection: Binding(
                                       get: { chosen?.id },
                                       set: { selectedWorkoutID = $0 }
                                   )) {
                                ForEach(candidates) { option in
                                    Text(option.workout.title + " · " +
                                         option.date.formatted(
                                            date: .abbreviated, time: .omitted
                                         ))
                                    .tag(Optional(option.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("studio-scenario-workout")

                            Picker(tr("What would you like to test?",
                                        "Hva vil du prøve?"),
                                   selection: $scenarioAction) {
                                Text(tr("Move workout", "Flytt økt")).tag("move")
                                Text(tr("Skip workout", "Hopp over økt")).tag("skip")
                            }
                            .pickerStyle(.segmented)
                            if scenarioAction == "move" {
                            Picker(tr("Try another date", "Prøv en annen dato"),
                                   selection: $targetDayID) {
                                Text(tr("Choose a date", "Velg dato"))
                                    .tag(Optional<UUID>.none)
                                ForEach(targets) { target in
                                    Text(target.date.formatted(
                                        date: .abbreviated, time: .omitted
                                    ))
                                    .tag(Optional(target.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("studio-scenario-target")
                            }

                            if let chosen, scenarioAction == "skip" {
                                skippedProjection(plan: plan, chosen: chosen)
                            } else if let chosen, let destination, validChange {
                                projection(plan: plan, chosen: chosen,
                                           destination: destination)
                            } else {
                                Text(tr(
                                    "Select another day to see the effect. Nothing changes while you preview.",
                                    "Velg en annen dag for å se effekten. Ingenting endres mens du forhåndsviser."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Button {
                                    showingApproval = true
                                } label: {
                                    Label(tr("Approve change", "Godkjenn endring"),
                                          systemImage: "checkmark")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(ATHLTHStudioStyle.ink)
                                .disabled(!validChange)

                                if let lastSkippedID {
                                    Button {
                                        session.setPlanSessionSkipped(
                                            planID: planID,
                                            sessionID: lastSkippedID,
                                            skipped: false
                                        )
                                        self.lastSkippedID = nil
                                    } label: {
                                        Label(tr("Undo skipped workout",
                                                 "Angre hoppet over økt"),
                                              systemImage: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let onAddWorkout {
                                    Button(action: onAddWorkout) {
                                        Label(tr("Add workout in plan editor",
                                                 "Legg til økt i planbygger"),
                                              systemImage: "plus.circle")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                if let onAskCoach {
                                    Button(action: onAskCoach) {
                                        Label("ATHLTH Coach",
                                              systemImage: "sparkles")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(ATHLTHStudioStyle.gold)
                                }
                            }
                        }
                        .padding(20)
                        .background(.white,
                                    in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        ContentUnavailableView(
                            tr("No editable workouts", "Ingen redigerbare økter"),
                            systemImage: "calendar.badge.exclamationmark",
                            description: Text(tr(
                                "Completed and past workouts remain protected.",
                                "Fullførte og tidligere økter er beskyttet."
                            ))
                        )
                    }

                    Text(tr(
                        "Your Coach is available beside Studio. You decide whether to apply each proposed adjustment.",
                        "Coachen kan åpnes ved siden av Studio. Du bestemmer selv om et forslag skal gjennomføres."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(ATHLTHStudioStyle.canvas.ignoresSafeArea())
            .navigationTitle("Scenario Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Close", "Lukk")) { dismiss() }
                }
            }
        }
        .confirmationDialog(
            scenarioAction == "skip"
                ? tr("Skip this planned workout?", "Hoppe over denne økten?")
                : tr("Move this planned workout?", "Flytte denne planlagte økten?"),
            isPresented: $showingApproval,
            titleVisibility: .visible
        ) {
            Button(
                scenarioAction == "skip"
                    ? tr("Skip workout", "Hopp over økten")
                    : tr("Move workout", "Flytt økten")
            ) { applyChange() }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {}
        } message: {
            Text(tr(
                "ATHLTH checks the current plan version and workout completion before saving.",
                "ATHLTH kontrollerer siste planversjon og fullføringsstatus før lagring."
            ))
        }
        .alert(
            tr("The plan was not changed", "Planen ble ikke endret"),
            isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func skippedProjection(
        plan: TrainingPlan, chosen: Candidate
    ) -> some View {
        let week = plan.weeks[chosen.weekIndex]
        let summary = ATHLTHStudioPlanWeekSummary.calculate(week)
        let minutes = max(0, chosen.workout.durationMinutes ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("BEFORE → AFTER", "FØR → ETTER"))
                .font(.caption.weight(.bold))
                .foregroundStyle(ATHLTHStudioStyle.gold)
            ATHLTHStudioMetricCard(
                title: tr("Week \(week.weekNumber)", "Uke \(week.weekNumber)"),
                value: "\(summary.knownMinutes) → \(max(0, summary.knownMinutes - minutes)) min",
                note: tr(
                    "Planned duration if you skip this workout",
                    "Planlagt varighet hvis du hopper over økten"
                )
            )
            Text(tr(
                "The workout remains in the plan with a skipped status. Completed Health recordings are not changed.",
                "Økten blir liggende i planen, men markeres som hoppet over. Gjennomførte Health-målinger endres ikke."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func projection(
        plan: TrainingPlan, chosen: Candidate,
        destination: Target
    ) -> some View {
        let sourceWeek = plan.weeks[chosen.weekIndex]
        let targetWeek = plan.weeks[destination.weekIndex]
        let source = ATHLTHStudioPlanWeekSummary.calculate(sourceWeek)
        let target = ATHLTHStudioPlanWeekSummary.calculate(targetWeek)
        let minutes = max(0, chosen.workout.durationMinutes ?? 0)
        let sameWeek = chosen.weekIndex == destination.weekIndex
        let gapDays = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: chosen.date),
            to: Calendar.current.startOfDay(for: destination.date)
        ).day ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("BEFORE → AFTER", "FØR → ETTER"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(ATHLTHStudioStyle.gold)
            HStack(spacing: 12) {
                ATHLTHStudioMetricCard(
                    title: tr("Week \(sourceWeek.weekNumber)", "Uke \(sourceWeek.weekNumber)"),
                    value: "\(source.knownMinutes) → \(sameWeek ? source.knownMinutes : max(0, source.knownMinutes - minutes)) min",
                    note: tr("Planned training time", "Planlagt treningstid")
                )
                if !sameWeek {
                    ATHLTHStudioMetricCard(
                        title: tr("Week \(targetWeek.weekNumber)", "Uke \(targetWeek.weekNumber)"),
                        value: "\(target.knownMinutes) → \(target.knownMinutes + minutes) min",
                        note: tr("Planned training time", "Planlagt treningstid")
                    )
                }
            }
            Text(tr(
                "Moving \(chosen.workout.title) changes its scheduled day by \(abs(gapDays)) days. All other sessions stay unchanged.",
                "Flytting av \(chosen.workout.title) forskyver økten \(abs(gapDays)) dager. Alle andre økter forblir uendret."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if chosen.workout.durationMinutes == nil {
                Label(tr(
                    "Duration is missing; the time comparison is incomplete.",
                    "Økten mangler varighet. Sammenligningen av treningstid er ufullstendig."
                ), systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            let targetDay = targetWeek.days.first {
                $0.id == destination.id
            }
            if targetDay?.sessions.contains(where: { !$0.isExplicitRestDay }) == true {
                Label(tr(
                    "The target day already has training. Review total workload and recovery before combining sessions.",
                    "Det er allerede trening på måldagen. Vurder totalbelastning og restitusjon før du kombinerer økter."
                ), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(ATHLTHStudioStyle.gold)
            }
        }
    }

    private func applyChange() {
        guard validChange, let plan, let chosen else { return }
        guard session.trainingPlan(withID: planID)?.version == plan.version
        else {
            errorText = tr(
                "The plan changed on another screen or device. Review the latest plan first.",
                "Planen ble endret på en annen skjerm eller enhet. Kontroller siste versjon først."
            )
            return
        }
        if scenarioAction == "skip" {
            guard !session.isPlanSessionCompleted(
                planID: planID, sessionID: chosen.id,
                healthWorkouts: health.workouts,
                strengthHistory: strength.workoutHistory
            ), !session.isPlanSessionSkipped(
                planID: planID, sessionID: chosen.id
            ) else {
                errorText = tr(
                    "The workout is no longer eligible for skipping.",
                    "Økten kan ikke lenger markeres som hoppet over."
                )
                return
            }
            session.setPlanSessionSkipped(
                planID: planID, sessionID: chosen.id, skipped: true
            )
            lastSkippedID = chosen.id
            selectedWorkoutID = nil
            return
        }
        guard let target = destination else { return }
        let success = session.movePlanStudioWorkout(
            planID: planID, workoutID: chosen.id,
            targetDate: target.date, expectedVersion: plan.version,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        if success {
            selectedWorkoutID = nil
            targetDayID = nil
            dismiss()
        } else {
            errorText = tr(
                "The workout may have been completed or modified. No change was saved.",
                "Økten kan være fullført eller endret. Ingen endring ble lagret."
            )
        }
    }
}
