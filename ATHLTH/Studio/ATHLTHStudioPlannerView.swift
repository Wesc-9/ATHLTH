import SwiftUI

/// Landscape-first overview of the real stored training plan.
/// All edits are delegated to the existing training plan editor; a Studio
/// preview must never silently rewrite scheduled dates or recorded workouts.
struct ATHLTHStudioPlannerView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore
    @State private var selectedWeekIndex = 0
    @State private var showsAllWeeks = false
    @State private var showingTrainingEditor = false
    @State private var trainRequest: ATHLTHTrainNavigationRequest? = .plan
    @State private var additionalMinutes: Double = 30
    @State private var scenario = 0
    @State private var dragMode: DragMode = .move
    @State private var moveError: String?

    private enum DragMode: String, CaseIterable, Identifiable {
        case move, copy
        var id: String { rawValue }
    }

    private var plan: TrainingPlan? {
        session.activePlan ?? session.scheduledPlans.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Plan Studio")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(ATHLTHStudioStyle.ink)
                        Text(ATHLTHLocalization.choose(
                            english: "Understand your weeks before changing them.",
                            norwegian: "Se sammenhengen mellom ukene før du gjør endringer."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        trainRequest = .plan
                        showingTrainingEditor = true
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "Open plan editor", norwegian: "Åpne planredigering"
                        ), systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let plan, !plan.weeks.isEmpty {
                    let safeWeek = min(selectedWeekIndex, plan.weeks.count - 1)
                    let week = plan.weeks[safeWeek]
                    Text(plan.title)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 18) {
                        Toggle(ATHLTHLocalization.choose(
                            english: "Show entire training block", norwegian: "Vis hele treningsblokken"
                        ), isOn: $showsAllWeeks)
                        .toggleStyle(.switch)
                        .fixedSize()
                        Spacer()
                        Text(ATHLTHLocalization.choose(
                            english: "Select a week or inspect the entire block.",
                            norwegian: "Velg én uke eller se hele treningsblokken."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    savedWorkoutLibrary
                    if showsAllWeeks {
                        LazyVStack(spacing: 16) {
                            ForEach(Array(plan.weeks.enumerated()), id: \.element.id) { index, fullWeek in
                                weekLayout(fullWeek, plan: plan, weekIndex: index)
                            }
                        }
                    } else {
                        weekPicker(plan.weeks)
                        weekLayout(week, plan: plan, weekIndex: safeWeek)
                    }
                    scenarioLab(week)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(ATHLTHLocalization.choose(
                            english: "No active training plan",
                            norwegian: "Ingen aktiv treningsplan"
                        ))
                        .font(.title3.weight(.semibold))
                        Text(ATHLTHLocalization.choose(
                            english: "Create a plan with the existing ATHLTH builder, then review it here in landscape.",
                            norwegian: "Opprett en plan med ATHLTH-planleggeren, og se den her i liggende visning."
                        ))
                        .foregroundStyle(.secondary)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(26)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: session.activePlan?.id) { _, _ in
            selectedWeekIndex = 0
        }
        .sheet(isPresented: $showingTrainingEditor) {
            ATHLTHTrainView(navigationRequest: $trainRequest, isActive: true)
        }
        .alert(
            ATHLTHLocalization.choose(english: "Could not update plan", norwegian: "Kunne ikke oppdatere planen"),
            isPresented: Binding(
                get: { moveError != nil },
                set: { if !$0 { moveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { moveError = nil }
        } message: {
            Text(moveError ?? "")
        }
    }

    private var savedWorkoutLibrary: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(ATHLTHLocalization.choose(
                    english: "My saved workouts", norwegian: "Mine lagrede treningsøkter"
                ), systemImage: "square.stack")
                .font(.headline)
                Spacer()
                Text(ATHLTHLocalization.choose(
                    english: "Drag a saved workout into a future plan day",
                    norwegian: "Dra en lagret økt til en fremtidig dag i planen"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if session.savedWorkoutTemplates.isEmpty {
                Text(ATHLTHLocalization.choose(
                    english: "Your saved workouts will appear here.",
                    norwegian: "Lagrede treningsøkter vises her."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(session.savedWorkoutTemplates.prefix(20)) { item in
                            Label(item.title, systemImage: item.kind.systemImage)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(minWidth: 145, minHeight: 46)
                                .padding(.horizontal, 15)
                                .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 13))
                                .draggable("library:\(item.id.uuidString)")
                                .accessibilityHint(ATHLTHLocalization.choose(
                                    english: "Drag to a future day in the training plan",
                                    norwegian: "Dra til en fremtidig dag i treningsplanen"
                                ))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func weekPicker(_ weeks: [TrainingPlanWeek]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Array(weeks.enumerated()), id: \.element.id) { index, week in
                    Button {
                        selectedWeekIndex = index
                    } label: {
                        Text("\(ATHLTHLocalization.choose(english: "Week", norwegian: "Uke")) \(week.weekNumber)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(
                                selectedWeekIndex == index ? ATHLTHStudioStyle.ink : .white,
                                in: Capsule()
                            )
                            .foregroundStyle(selectedWeekIndex == index ? .white : ATHLTHStudioStyle.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func weekLayout(_ week: TrainingPlanWeek, plan: TrainingPlan, weekIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text(ATHLTHLocalization.choose(
                    english: "Week schedule", norwegian: "Ukeplan"
                ))
                .font(.headline)
                Spacer()
                Picker(ATHLTHLocalization.choose(english: "Drop action", norwegian: "Slipp-handling"), selection: $dragMode) {
                    Text(ATHLTHLocalization.choose(english: "Move", norwegian: "Flytt")).tag(DragMode.move)
                    Text(ATHLTHLocalization.choose(english: "Copy", norwegian: "Kopier")).tag(DragMode.copy)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Text("\(week.days.reduce(0) { $0 + $1.sessions.filter { !$0.isExplicitRestDay }.count }) " +
                    ATHLTHLocalization.choose(english: "sessions", norwegian: "økter"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(ATHLTHLocalization.choose(
                english: "Drag a future workout to another day. Finished workouts stay protected.",
                norwegian: "Dra en fremtidig økt til en annen dag. Fullførte økter er beskyttet."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(week.days.sorted { $0.dayIndex < $1.dayIndex }) { day in
                        dayCard(day, plan: plan, weekIndex: weekIndex)
                            .frame(minWidth: 155, maxWidth: .infinity, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func dayCard(_ day: TrainingPlanDay, plan: TrainingPlan, weekIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.title.isEmpty ? "\(ATHLTHLocalization.choose(english: "Day", norwegian: "Dag")) \(day.dayIndex + 1)" : day.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if day.sessions.isEmpty {
                Label(ATHLTHLocalization.choose(english: "Rest", norwegian: "Hvile"), systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(day.sessions) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        Image(systemName: item.isExplicitRestDay ? "moon.zzz" : item.kind.systemImage)
                            .foregroundStyle(ATHLTHStudioStyle.gold)
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let minutes = item.durationMinutes, !item.isExplicitRestDay {
                            Text("\(minutes) min").font(.caption2).foregroundStyle(.secondary)
                        }
                        if !item.isExplicitRestDay {
                            Button {
                                trainRequest = .workout(planID: plan.id, workoutID: item.id)
                                showingTrainingEditor = true
                            } label: {
                                Label(ATHLTHLocalization.choose(
                                    english: "Details", norwegian: "Detaljer"
                                ), systemImage: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ATHLTHStudioStyle.gold)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(ATHLTHStudioStyle.outline.opacity(0.5)))
                    .draggable(item.id.uuidString)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 170, alignment: .top)
        .background(ATHLTHStudioStyle.canvas, in: RoundedRectangle(cornerRadius: 15))
        .dropDestination(for: String.self) { values, _ in
            guard let raw = values.first,
                  let start = plan.startDate,
                  let target = Calendar.current.date(
                    byAdding: .day,
                    value: weekIndex * 7 + day.dayIndex - 1,
                    to: Calendar.current.startOfDay(for: start)
                  ) else { return false }
            guard session.trainingPlan(withID: plan.id)?.version == plan.version,
                  Calendar.current.startOfDay(for: target) >= Calendar.current.startOfDay(for: .now)
            else { return false }
            let success: Bool
            if raw.hasPrefix("library:"),
               let libraryID = UUID(uuidString: String(raw.dropFirst("library:".count))) {
                success = session.insertSavedWorkoutIntoPlan(
                    templateID: libraryID,
                    planID: plan.id,
                    dayID: day.id
                )
            } else if let workoutID = UUID(uuidString: raw) {
                if dragMode == .copy {
                    success = session.copyPlanStudioWorkout(
                        planID: plan.id,
                        sourceWorkoutID: workoutID,
                        targetDayID: day.id,
                        expectedVersion: plan.version
                    )
                } else {
                    success = session.movePlanStudioWorkout(
                        planID: plan.id,
                        workoutID: workoutID,
                        targetDate: target,
                        expectedVersion: plan.version,
                        healthWorkouts: health.workouts,
                        strengthHistory: strength.workoutHistory
                    )
                }
            } else {
                return false
            }
            if !success {
                moveError = ATHLTHLocalization.choose(
                    english: "The workout may be completed, in the past, or the plan may have changed. Reload and try again.",
                    norwegian: "Økten kan være fullført eller i fortiden, eller planen kan ha blitt endret. Oppdater og prøv igjen."
                )
            }
            return success
        }
    }

    private func scenarioLab(_ week: TrainingPlanWeek) -> some View {
        let planned = week.days.flatMap(\.sessions).filter { !$0.isExplicitRestDay }
        let minutes = planned.reduce(0) { $0 + max(0, $1.durationMinutes ?? 0) }
        let delta = scenario == 1 ? Int(additionalMinutes) : scenario == 2 ? -Int(additionalMinutes) : 0
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(ATHLTHStudioStyle.gold)
                Text("Scenario Lab").font(.headline)
                Spacer()
                Text(ATHLTHLocalization.choose(english: "Preview only", norwegian: "Kun forhåndsvisning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker(ATHLTHLocalization.choose(english: "Scenario", norwegian: "Scenario"), selection: $scenario) {
                Text(ATHLTHLocalization.choose(english: "Current plan", norwegian: "Nåværende plan")).tag(0)
                Text(ATHLTHLocalization.choose(english: "More training", norwegian: "Mer trening")).tag(1)
                Text(ATHLTHLocalization.choose(english: "Lighter week", norwegian: "Lettere uke")).tag(2)
            }
            .pickerStyle(.segmented)
            if scenario != 0 {
                Slider(value: $additionalMinutes, in: 10...120, step: 5) {
                    Text(ATHLTHLocalization.choose(english: "Minutes to adjust", norwegian: "Minutter som justeres"))
                }
            }
            HStack(spacing: 16) {
                ATHLTHStudioMetricCard(
                    title: ATHLTHLocalization.choose(english: "Current plan", norwegian: "Gjeldende plan"),
                    value: "\(minutes) min",
                    note: "\(planned.count) " + ATHLTHLocalization.choose(english: "sessions", norwegian: "økter")
                )
                ATHLTHStudioMetricCard(
                    title: ATHLTHLocalization.choose(english: "Scenario", norwegian: "Alternativ"),
                    value: "\(max(0, minutes + delta)) min",
                    note: ATHLTHLocalization.choose(english: "Estimated weekly duration", norwegian: "Beregnet ukesvarighet")
                )
            }
            Text(ATHLTHLocalization.choose(
                english: "A duration-only illustration; not a recovery, injury-risk or load prediction. No workouts are changed.",
                norwegian: "Illustrerer kun varighet – ikke restitusjon, skaderisiko eller treningsbelastning. Ingen økter endres."
            ))
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}
