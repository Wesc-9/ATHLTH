import SwiftUI

/// Transparently separates completed, skipped, upcoming and unreviewed past
/// workouts, without guessing completion or changing saved workouts.
struct ATHLTHPlanWeeklyFollowThroughView: View {
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var health: HealthKitManager
    @EnvironmentObject private var strength: StrengthWorkoutStore

    let plan: TrainingPlan
    let onSelect: (UUID, UUID?) -> Void
    @State private var showsAll = false
    @State private var showsSuggestionPreview = false
    @State private var showsMovePreview = false
    @State private var movePreviewUnavailable = false
    @State private var moveSaved = false
    @State private var lastApprovedSessionID: UUID?
    @State private var previewEfforts: [UUID: ATHLTHPlanWeeklyFollowThrough.PlannedEffort] = [:]
    @State private var showsIntensityPreview = false
    @State private var showsTrainingDetails = false

    var body: some View {
        // Always use the persisted plan rather than a possibly stale
        // value captured when the parent first presented this screen.
        let currentPlan = session.trainingPlan(withID: plan.id) ?? plan
        let report = ATHLTHPlanWeeklyFollowThrough.inspect(
            plan: currentPlan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let load = ATHLTHPlanWeeklyFollowThrough.plannedLoadSummary(plan: currentPlan)
        let weeklyLoads = ATHLTHPlanWeeklyFollowThrough.weeklyLoadSummaries(plan: currentPlan)
        let volumeChanges = ATHLTHPlanWeeklyFollowThrough.weeklyVolumeChanges(plan: currentPlan)
        let intensity = ATHLTHPlanWeeklyFollowThrough.effortDistribution(
            plan: currentPlan, effortBySessionID: previewEfforts
        )
        let weeklyEfforts = ATHLTHPlanWeeklyFollowThrough.weeklyEffortSummaries(
            plan: currentPlan, effortBySessionID: previewEfforts
        )
        let nextWorkout = ATHLTHPlanWeeklyFollowThrough.nextWorkout(
            plan: currentPlan, store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentWeekIndex: Int? = currentPlan.startDate.flatMap { start in
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: start), to: today
            ).day ?? -1
            let index = days / 7
            return days >= 0 && index < currentPlan.weeks.count ? index : nil
        }
        let relevant = report.relevantWeeks
        let movePreview = ATHLTHPlanWeeklyFollowThrough.previewNextSafeMove(
            plan: currentPlan,
            store: session,
            healthWorkouts: health.workouts,
            strengthHistory: strength.workoutHistory
        )

        ATHLTHPlanSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text("ATHLTH / WEEKLY REVIEW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(ATHLTHPlanDesign.accent)

                Text(ATHLTHLocalization.choose(
                    english: "What happened this week?",
                    norwegian: "Hva har skjedd i treningsuken?"
                ))
                .font(.system(size: 23, weight: .semibold, design: .serif))
                .foregroundStyle(ATHLTHPlanDesign.ink)

                Text(ATHLTHLocalization.choose(
                    english: "Confirmed activity, skipped workouts and future sessions are separated. Past sessions without a recorded result are shown for review, not marked as failures.",
                    norwegian: "Fullførte økter, økter du har hoppet over og kommende økter holdes adskilt. Tidligere økter uten registrert resultat vises for gjennomgang, ikke som mislykkede."
                ))
                .font(.caption)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 9) {
                Button {
                    showsIntensityPreview.toggle()
                } label: {
                    HStack {
                        Label(ATHLTHLocalization.choose(
                            english: "Workout intensity",
                            norwegian: "Intensitet i treningsplanen"
                        ), systemImage: "waveform.path.ecg")
                        Spacer()
                        Image(systemName: showsIntensityPreview ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)

                if showsIntensityPreview {
                    Text(ATHLTHLocalization.choose(
                        english: "Try assigning easy, moderate or hard intensity to sessions. Intensity choices are saved locally for this plan.",
                        norwegian: "Prøv å angi rolig, moderat eller hard intensitet for øktene. Intensitetsvalgene lagres lokalt for denne planen."
                    ))
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    ForEach(currentPlan.weeks) { week in
                    ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                            ForEach(day.sessions) { workout in
                                HStack(spacing: 8) {
                                    Text(workout.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Menu {
                                        Button(ATHLTHLocalization.choose(
                                            english: "Not specified", norwegian: "Ikke angitt"
                                        )) { updateEffort(nil, for: workout.id, plan: currentPlan) }
                                        Button(ATHLTHLocalization.choose(
                                            english: "Easy", norwegian: "Rolig"
                                        )) { updateEffort(.easy, for: workout.id, plan: currentPlan) }
                                        Button(ATHLTHLocalization.choose(
                                            english: "Moderate", norwegian: "Moderat"
                                        )) { updateEffort(.moderate, for: workout.id, plan: currentPlan) }
                                        Button(ATHLTHLocalization.choose(
                                            english: "Hard", norwegian: "Hard"
                                        )) { updateEffort(.hard, for: workout.id, plan: currentPlan) }
                                    } label: {
                                        Text(previewEfforts[workout.id] == .easy
                                             ? ATHLTHLocalization.choose(english: "Easy", norwegian: "Rolig")
                                             : previewEfforts[workout.id] == .moderate
                                             ? ATHLTHLocalization.choose(english: "Moderate", norwegian: "Moderat")
                                             : previewEfforts[workout.id] == .hard
                                             ? ATHLTHLocalization.choose(english: "Hard", norwegian: "Hard")
                                             : ATHLTHLocalization.choose(english: "Set intensity", norwegian: "Velg intensitet"))
                                        .font(.caption.weight(.medium))
                                    }
                                }
                            }
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Easy \(intensity.easyMinutes) min · Moderate \(intensity.moderateMinutes) min · Hard \(intensity.hardMinutes) min · Unknown \(intensity.unknownMinutes) min",
                        norwegian: "Rolig \(intensity.easyMinutes) min · Moderat \(intensity.moderateMinutes) min · Hard \(intensity.hardMinutes) min · Ukjent \(intensity.unknownMinutes) min"
                    ))
                    .font(.caption)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ATHLTHLocalization.choose(
                            english: "Intensity by week", norwegian: "Intensitet per uke"
                        ))
                        .font(.caption.weight(.semibold))
                        ForEach(weeklyEfforts) { week in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(ATHLTHLocalization.choose(
                                        english: "Week \(week.weekNumber)",
                                        norwegian: "Uke \(week.weekNumber)"
                                    ))
                                    .font(.caption.weight(.medium))
                                    Spacer()
                                    Text(ATHLTHLocalization.choose(
                                        english: "\(week.hardDays) hard days",
                                        norwegian: "\(week.hardDays) harde dager"
                                    ))
                                    .font(.caption2)
                                }
                                Text(ATHLTHLocalization.choose(
                                    english: "Easy \(week.easyMinutes) · Moderate \(week.moderateMinutes) · Hard \(week.hardMinutes) · Unknown \(week.unknownMinutes) min",
                                    norwegian: "Rolig \(week.easyMinutes) · Moderat \(week.moderateMinutes) · Hard \(week.hardMinutes) · Ukjent \(week.unknownMinutes) min"
                                ))
                                .font(.caption2)
                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            }
                        }
                    }
                    if intensity.adjacentHardDayPairs > 0 {
                        Label(ATHLTHLocalization.choose(
                            english: "\(intensity.adjacentHardDayPairs) adjacent pairs of hard training days. Review your plan.",
                            norwegian: "\(intensity.adjacentHardDayPairs) par med harde treningsdager etter hverandre. Vurder fordelingen."
                        ), systemImage: "exclamationmark.circle")
                        .font(.caption)
                    }
                    Button(ATHLTHLocalization.choose(
                        english: "Clear intensity choices", norwegian: "Fjern intensitetsvalg"
                    )) { clearEfforts(plan: currentPlan) }
                    .font(.caption)
                }
            }
            .foregroundStyle(ATHLTHPlanDesign.ink)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let currentWeekIndex {
                let week = currentPlan.weeks[currentWeekIndex]
                let summary = weeklyLoads[currentWeekIndex]
                let weekStatus = report.weeks[currentWeekIndex]
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label(ATHLTHLocalization.choose(
                            english: "This week", norwegian: "Denne uken"
                        ), systemImage: "calendar")
                        .font(.headline)
                        Spacer()
                        Text(ATHLTHLocalization.choose(
                            english: "Week \(currentWeekIndex + 1)",
                            norwegian: "Uke \(currentWeekIndex + 1)"
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    }
                    HStack(spacing: 12) {
                        Label(ATHLTHLocalization.choose(
                            english: "\(summary.activeDays) training days",
                            norwegian: "\(summary.activeDays) treningsdager"
                        ), systemImage: "figure.run")
                        Label(ATHLTHLocalization.choose(
                            english: "\(summary.plannedMinutes) min planned",
                            norwegian: "\(summary.plannedMinutes) min planlagt"
                        ), systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    HStack(spacing: 12) {
                        Label("\(weekStatus.completed)", systemImage: "checkmark.circle.fill")
                        Label("\(weekStatus.upcoming)", systemImage: "calendar")
                        if weekStatus.needsReview > 0 {
                            Label("\(weekStatus.needsReview)", systemImage: "questionmark.circle")
                        }
                        if weekStatus.skipped > 0 {
                            Label("\(weekStatus.skipped)", systemImage: "minus.circle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .accessibilityLabel(ATHLTHLocalization.choose(
                        english: "\(weekStatus.completed) completed, \(weekStatus.upcoming) upcoming, \(weekStatus.needsReview) need review, \(weekStatus.skipped) skipped",
                        norwegian: "\(weekStatus.completed) fullført, \(weekStatus.upcoming) kommende, \(weekStatus.needsReview) trenger gjennomgang, \(weekStatus.skipped) hoppet over"
                    ))
                    ForEach(week.days.sorted(by: { $0.dayIndex < $1.dayIndex })) { day in
                        if !day.sessions.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Text(
                                    currentPlan.startDate.flatMap { start in
                                        calendar.date(
                                            byAdding: .day,
                                            value: currentWeekIndex * 7 + day.dayIndex - 1,
                                            to: calendar.startOfDay(for: start)
                                        )
                                    }?.formatted(.dateTime.weekday(.abbreviated))
                                    ?? ATHLTHLocalization.choose(
                                        english: "Day \(day.dayIndex)",
                                        norwegian: "Dag \(day.dayIndex)"
                                    )
                                )
                                .font(.caption.weight(.semibold))
                                .frame(width: 65, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(day.sessions) { workout in
                                        let completed = session.isPlanSessionCompleted(
                                            planID: currentPlan.id, sessionID: workout.id,
                                            healthWorkouts: health.workouts,
                                            strengthHistory: strength.workoutHistory
                                        )
                                        let skipped = session.isPlanSessionSkipped(
                                            planID: currentPlan.id, sessionID: workout.id
                                        )
                                        let dayDate = currentPlan.startDate.flatMap { start in
                                            calendar.date(
                                                byAdding: .day,
                                                value: currentWeekIndex * 7 + day.dayIndex - 1,
                                                to: calendar.startOfDay(for: start)
                                            )
                                        }
                                        let effectiveDate = workout.scheduledStart ?? dayDate
                                        let needsReview = !completed && !skipped
                                            && (effectiveDate.map { calendar.startOfDay(for: $0) < today } ?? false)
                                        if needsReview {
                                            Button {
                                                onSelect(week.id, day.id)
                                            } label: {
                                                Label(ATHLTHLocalization.choose(
                                                    english: "Review \(workout.title)",
                                                    norwegian: "Gjennomgå \(workout.title)"
                                                ), systemImage: "questionmark.circle")
                                                .font(.caption.weight(.semibold))
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        HStack(spacing: 5) {
                                            Image(systemName: completed
                                                  ? "checkmark.circle.fill"
                                                  : skipped ? "minus.circle"
                                                  : "circle")
                                                .foregroundStyle(completed
                                                    ? ATHLTHPlanDesign.accent
                                                    : ATHLTHPlanDesign.secondaryInk)
                                                .accessibilityHidden(true)
                                            Text(workout.title)
                                                .font(.subheadline)
                                                .lineLimit(2)
                                            Spacer(minLength: 4)
                                            Text(completed
                                                 ? ATHLTHLocalization.choose(
                                                     english: "Done", norwegian: "Fullført"
                                                   )
                                                 : skipped
                                                 ? ATHLTHLocalization.choose(
                                                     english: "Skipped", norwegian: "Hoppet over"
                                                   )
                                                 : needsReview
                                                 ? ATHLTHLocalization.choose(
                                                     english: "Needs review", norwegian: "Trenger gjennomgang"
                                                   )
                                                 : ATHLTHLocalization.choose(
                                                     english: "Planned", norwegian: "Planlagt"
                                                   ))
                                                .font(.caption2)
                                                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                        }
                                    }
                                }
                                Spacer(minLength: 4)
                                Button {
                                    onSelect(week.id, day.id)
                                } label: {
                                    Image(systemName: "arrow.up.right")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(ATHLTHLocalization.choose(
                                    english: "Open planned day",
                                    norwegian: "Åpne planlagt dag"
                                ))
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if let nextWorkout {
                VStack(alignment: .leading, spacing: 7) {
                    Label(ATHLTHLocalization.choose(
                        english: "Your next planned workout",
                        norwegian: "Din neste planlagte økt"
                    ), systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    Text(nextWorkout.title)
                        .font(.title3.weight(.semibold))
                    Text(nextWorkout.date.formatted(
                        .dateTime.weekday(.wide).day().month(.abbreviated)
                    ))
                    .font(.caption)
                    if let minutes = nextWorkout.durationMinutes, minutes > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "\(minutes) planned minutes",
                            norwegian: "\(minutes) planlagte minutter"
                        ))
                        .font(.caption)
                    }
                    Button {
                        onSelect(nextWorkout.weekID, nextWorkout.dayID)
                    } label: {
                        Label(ATHLTHLocalization.choose(
                            english: "View workout in plan",
                            norwegian: "Se økten i planen"
                        ), systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if load.estimatedMinutes > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    Button {
                        showsTrainingDetails.toggle()
                    } label: {
                        HStack {
                            Label(ATHLTHLocalization.choose(
                                english: "Training volume and weekly trends",
                                norwegian: "Treningsmengde og utvikling"
                            ), systemImage: "chart.bar.xaxis")
                            Spacer()
                            Image(systemName: showsTrainingDetails ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    if showsTrainingDetails {
                    Label(
                        ATHLTHLocalization.choose(
                            english: "Planned training volume",
                            norwegian: "Planlagt treningsmengde"
                        ),
                        systemImage: "chart.bar.xaxis"
                    )
                    .font(.subheadline.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "\(load.estimatedMinutes) minutes across the plan",
                        norwegian: "\(load.estimatedMinutes) minutter i hele planen"
                    ))
                    .font(.title3.weight(.semibold))
                    Text(ATHLTHLocalization.choose(
                        english: "Running \(load.runningMinutes) min · Strength \(load.strengthMinutes) min · Walking \(load.walkingMinutes) min",
                        norwegian: "Løping \(load.runningMinutes) min · Styrke \(load.strengthMinutes) min · Gange \(load.walkingMinutes) min"
                    ))
                    .font(.caption)
                    if load.unspecifiedMinutes > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "\(load.unspecifiedMinutes) minutes in other workout types",
                            norwegian: "\(load.unspecifiedMinutes) minutter i andre økttyper"
                        ))
                        .font(.caption2)
                    }
                    if load.consecutiveLongDayPairs > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "\(load.consecutiveLongDayPairs) adjacent pairs of days with at least 60 planned minutes. Review their intensity before training.",
                                norwegian: "\(load.consecutiveLongDayPairs) par med påfølgende dager som har minst 60 planlagte minutter. Vurder intensiteten før trening."
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                    }
                    ForEach(weeklyLoads) { week in
                        HStack(spacing: 8) {
                            Text(ATHLTHLocalization.choose(
                                english: "Week \(week.weekNumber)",
                                norwegian: "Uke \(week.weekNumber)"
                            ))
                            .font(.caption.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(ATHLTHLocalization.choose(
                                english: "\(week.plannedMinutes) min · \(week.activeDays) workout days",
                                norwegian: "\(week.plannedMinutes) min · \(week.activeDays) treningsdager"
                            ))
                            .font(.caption)
                        }
                        if week.adjacentLongDayPairs > 0 {
                            Text(ATHLTHLocalization.choose(
                                english: "\(week.adjacentLongDayPairs) adjacent long-day pairs in this week",
                                norwegian: "\(week.adjacentLongDayPairs) par med lange treningsdager etter hverandre denne uken"
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    ForEach(volumeChanges, id: \.currentWeekNumber) { change in
                        if let percent = change.changePercent {
                            Text(ATHLTHLocalization.choose(
                                english: "Week \(change.currentWeekNumber) vs \(change.previousWeekNumber): \(percent >= 0 ? "+" : "")\(percent)% planned minutes",
                                norwegian: "Uke \(change.currentWeekNumber) mot \(change.previousWeekNumber): \(percent >= 0 ? "+" : "")\(percent) % planlagte minutter"
                            ))
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        } else {
                            Text(ATHLTHLocalization.choose(
                                english: "Week \(change.currentWeekNumber): no percentage comparison (previous week has no entered minutes)",
                                norwegian: "Uke \(change.currentWeekNumber): ingen prosentvis sammenligning (forrige uke mangler registrerte minutter)"
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                    }
                    Text(ATHLTHLocalization.choose(
                        english: "Based on entered durations only. Not a recovery score or measured training load.",
                        norwegian: "Basert kun på registrert varighet. Dette er ikke en restitusjonsscore eller målt treningsbelastning."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                }
                    }
                }
                .foregroundStyle(ATHLTHPlanDesign.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if report.total == 0 {
                Label(
                    ATHLTHLocalization.choose(
                        english: "No planned workouts to review yet.",
                        norwegian: "Ingen planlagte økter å gjennomgå ennå."
                    ),
                    systemImage: "calendar"
                )
                .font(.subheadline)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 13) {
                        metric(
                            report.completed,
                            label: ATHLTHLocalization.choose(
                                english: "Completed", norwegian: "Fullført"
                            )
                        )
                        metric(
                            report.upcoming,
                            label: ATHLTHLocalization.choose(
                                english: "Upcoming", norwegian: "Kommende"
                            )
                        )
                        metric(
                            report.needsReview,
                            label: ATHLTHLocalization.choose(
                                english: "Review", norwegian: "Gjennomgå"
                            )
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        ATHLTHPlanDesign.selectedSurface,
                        in: RoundedRectangle(
                            cornerRadius: ATHLTHPlanDesign.fieldRadius
                        )
                    )

                    if let completedPercent = report.completionPercent,
                       let accountedPercent = report.accountedPercent {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ATHLTHLocalization.choose(
                                english: "Completion: \(completedPercent)% · \(report.pastCompleted) of \(report.pastDated) past workouts",
                                norwegian: "Gjennomført: \(completedPercent) % · \(report.pastCompleted) av \(report.pastDated) tidligere økter"
                            ))
                            Text(ATHLTHLocalization.choose(
                                english: "Accounted for: \(accountedPercent)% · includes skipped workouts",
                                norwegian: "Avklart: \(accountedPercent) % · inkluderer økter hoppet over"
                            ))
                            Text(ATHLTHLocalization.choose(
                                english: "Unreviewed sessions are not assumed to be missed.",
                                norwegian: "Uavklarte økter regnes ikke automatisk som uteblitte."
                            ))
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)


                    }

                    if report.pastDated > 0 {
                        Text(ATHLTHLocalization.choose(
                            english: "Past workout breakdown: \(report.pastCompleted) completed · \(report.pastSkipped) skipped · \(report.pastUnreviewed) awaiting review. Skipped and unreviewed are different outcomes.",
                            norwegian: "Tidligere økter fordelt: \(report.pastCompleted) fullført · \(report.pastSkipped) hoppet over · \(report.pastUnreviewed) til gjennomgang. Hoppet over og uavklart er forskjellige resultater."
                        ))
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let suggestion = report.reviewSuggestion {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Suggested next step",
                                    norwegian: "Forslag til neste steg"
                                ),
                                systemImage: "lightbulb"
                            )
                            .font(.caption.weight(.semibold))
                            switch suggestion {
                            case .reviewUnresolved(let count):
                                Text(ATHLTHLocalization.choose(
                                    english: "\(count) past workouts have no recorded outcome. Review these sessions before adjusting your plan.",
                                    norwegian: "\(count) tidligere økter mangler registrert resultat. Gå gjennom øktene før du endrer planen."
                                ))
                            case .reviewSkipped(let count):
                                Text(ATHLTHLocalization.choose(
                                    english: "\(count) past workouts were marked skipped. Consider whether your schedule needs adjustment.",
                                    norwegian: "\(count) tidligere økter er markert som hoppet over. Vurder om treningsplanen bør tilpasses."
                                ))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ATHLTHLocalization.choose(
                                    english: "Before → after review",
                                    norwegian: "Før → etter gjennomgang"
                                ))
                                .font(.caption.weight(.semibold))
                                Text(ATHLTHLocalization.choose(
                                    english: "Before: \(report.pastCompleted) completed · \(report.pastSkipped) skipped · \(report.pastUnreviewed) unresolved.",
                                    norwegian: "Før: \(report.pastCompleted) fullført · \(report.pastSkipped) hoppet over · \(report.pastUnreviewed) uavklart."
                                ))
                                Text(ATHLTHLocalization.choose(
                                    english: "After opening: unchanged until you explicitly edit a session.",
                                    norwegian: "Etter åpning: uendret til du selv redigerer en økt."
                                ))
                            }
                            .font(.caption)
                            .foregroundStyle(ATHLTHPlanDesign.ink)

                            Text(ATHLTHLocalization.choose(
                                english: "Only you can decide to change the plan. No changes are made automatically.",
                                norwegian: "Du bestemmer selv om planen skal endres. Ingenting endres automatisk."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)

                            Button {
                                showsSuggestionPreview = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Review suggestion",
                                        norwegian: "Se gjennom forslaget"
                                    ),
                                    systemImage: "arrow.up.right"
                                )
                            }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                ATHLTHLocalization.choose(
                                    english: "Preview only — your plan will not change",
                                    norwegian: "Kun forhåndsvisning – planen endres ikke"
                                ),
                                isPresented: $showsSuggestionPreview,
                                titleVisibility: .visible
                            ) {
                                Button(ATHLTHLocalization.choose(
                                    english: "Open relevant week",
                                    norwegian: "Åpne aktuell uke"
                                )) {
                                    let matching = report.relevantWeeks.first {
                                        switch suggestion {
                                        case .reviewUnresolved: return $0.needsReview > 0
                                        case .reviewSkipped: return $0.pastSkipped > 0
                                        }
                                    }
                                    if let matching {
                                        let targetDay: UUID?
                                        switch suggestion {
                                        case .reviewUnresolved:
                                            targetDay = matching.firstReviewDayID
                                        case .reviewSkipped:
                                            targetDay = matching.firstSkippedDayID
                                        }
                                        onSelect(matching.id, targetDay)
                                    }
                                }
                                Button(ATHLTHLocalization.choose(
                                    english: "Cancel", norwegian: "Avbryt"
                                ), role: .cancel) { }
                            } message: {
                                Text(ATHLTHLocalization.choose(
                                    english: "You can inspect the recorded sessions in the existing plan editor. No workout will be moved, skipped or overwritten.",
                                    norwegian: "Du kan kontrollere de registrerte øktene i den eksisterende planredigeringen. Ingen økter flyttes, hoppes over eller overskrives."
                                ))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let movePreview, lastApprovedSessionID != movePreview.sessionID {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                ATHLTHLocalization.choose(
                                    english: "Possible schedule adjustment",
                                    norwegian: "Mulig justering av timeplanen"
                                ),
                                systemImage: "calendar.badge.clock"
                            )
                            .font(.caption.weight(.semibold))
                            Text(ATHLTHLocalization.choose(
                                english: "Preview: \(moveDayLabel(movePreview.sourceDayIndex, weekID: movePreview.weekID, plan: currentPlan)) → \(moveDayLabel(movePreview.destinationDayIndex, weekID: movePreview.weekID, plan: currentPlan)). The destination is empty.",
                                norwegian: "Forhåndsvisning: \(moveDayLabel(movePreview.sourceDayIndex, weekID: movePreview.weekID, plan: currentPlan)) → \(moveDayLabel(movePreview.destinationDayIndex, weekID: movePreview.weekID, plan: currentPlan)). Måldagen er ledig."
                            ))
                            .font(.caption)
                            Text(ATHLTHLocalization.choose(
                                english: "The new day has fewer adjacent active workouts and no occupied neighboring days. This is a calendar-spacing suggestion, not a recovery assessment. Nothing changes without approval.",
                                norwegian: "Den nye dagen har færre aktive økter på nabodagene og ingen opptatte nabodager. Dette er et forslag om kalenderfordeling, ikke en restitusjonsvurdering. Ingenting endres uten godkjenning."
                            ))
                            .font(.caption2)
                            .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                            Button {
                                showsMovePreview = true
                            } label: {
                                Label(
                                    ATHLTHLocalization.choose(
                                        english: "Review proposed move",
                                        norwegian: "Se gjennom foreslått flytting"
                                    ),
                                    systemImage: "arrow.up.right"
                                )
                            }
                            .buttonStyle(.bordered)
                            .confirmationDialog(
                                ATHLTHLocalization.choose(
                                    english: "Move \(moveDayLabel(movePreview.sourceDayIndex, weekID: movePreview.weekID, plan: currentPlan)) → \(moveDayLabel(movePreview.destinationDayIndex, weekID: movePreview.weekID, plan: currentPlan))?",
                                    norwegian: "Flytt \(moveDayLabel(movePreview.sourceDayIndex, weekID: movePreview.weekID, plan: currentPlan)) → \(moveDayLabel(movePreview.destinationDayIndex, weekID: movePreview.weekID, plan: currentPlan))?"
                                ),
                                isPresented: $showsMovePreview,
                                titleVisibility: .visible
                            ) {
                                Button(ATHLTHLocalization.choose(
                                    english: "Open workout in plan",
                                    norwegian: "Åpne økten i planen"
                                )) {
                                    guard let latest = session.trainingPlan(withID: plan.id),
                                          ATHLTHPlanWeeklyFollowThrough.validateMovePreview(
                                              movePreview,
                                              plan: latest,
                                              store: session,
                                              healthWorkouts: health.workouts,
                                              strengthHistory: strength.workoutHistory
                                          ) else {
                                        movePreviewUnavailable = true
                                        return
                                    }
                                    onSelect(movePreview.weekID, movePreview.sourceDayID)
                                }
                                Button(ATHLTHLocalization.choose(
                                    english: "Approve and move workout",
                                    norwegian: "Godkjenn og flytt økten"
                                )) {
                                    let success = ATHLTHPlanWeeklyFollowThrough.applyApprovedMove(
                                        movePreview,
                                        expectedVersion: currentPlan.version,
                                        store: session,
                                        planID: plan.id,
                                        healthWorkouts: health.workouts,
                                        strengthHistory: strength.workoutHistory
                                    )
                                    if success {
                                        lastApprovedSessionID = movePreview.sessionID
                                    }
                                    moveSaved = success
                                    movePreviewUnavailable = !success
                                }
                                Button(ATHLTHLocalization.choose(
                                    english: "Cancel", norwegian: "Avbryt"
                                ), role: .cancel) { }
                            } message: {
                                Text(ATHLTHLocalization.choose(
                                    english: "Day \(movePreview.sourceDayIndex) → day \(movePreview.destinationDayIndex). Only approval saves this move.",
                                    norwegian: "Dag \(movePreview.sourceDayIndex) → dag \(movePreview.destinationDayIndex). Kun godkjenning lagrer flyttingen."
                                ))
                            }
                            // A single alert presenter avoids conflicting
                            // modifiers on the same view hierarchy.
                            .alert(
                                moveSaved
                                    ? ATHLTHLocalization.choose(
                                        english: "Workout moved",
                                        norwegian: "Økten er flyttet"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Proposal no longer available",
                                        norwegian: "Forslaget er ikke lenger tilgjengelig"
                                    ),
                                isPresented: Binding(
                                    get: { moveSaved || movePreviewUnavailable },
                                    set: { presented in
                                        if !presented {
                                            moveSaved = false
                                            movePreviewUnavailable = false
                                        }
                                    }
                                )
                            ) {
                                Button("OK", role: .cancel) { }
                            } message: {
                                Text(moveSaved
                                    ? ATHLTHLocalization.choose(
                                        english: "Your approved change was saved.",
                                        norwegian: "Den godkjente endringen er lagret."
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "The plan changed or the workout is no longer eligible.",
                                        norwegian: "Planen er endret, eller økten kan ikke lenger flyttes."
                                    )
                                )
                            }
                        }
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                    }

                    if let trend = report.completedWeekTrend {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Completed weeks W\(trend.previous.number) → W\(trend.latest.number): \(trend.delta > 0 ? "+" : "")\(trend.delta) percentage points in completion. This describes recorded outcomes, not fitness progress.",
                                norwegian: "Avsluttede uker U\(trend.previous.number) → U\(trend.latest.number): \(trend.delta > 0 ? "+" : "")\(trend.delta) prosentpoeng i gjennomføring. Dette viser registrerte resultater, ikke formutvikling."
                            ),
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                        Text(ATHLTHLocalization.choose(
                            english: "Recorded change: completed \(trend.latest.pastCompleted - trend.previous.pastCompleted >= 0 ? "+" : "")\(trend.latest.pastCompleted - trend.previous.pastCompleted), skipped \(trend.latest.pastSkipped - trend.previous.pastSkipped >= 0 ? "+" : "")\(trend.latest.pastSkipped - trend.previous.pastSkipped), unreviewed \(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed >= 0 ? "+" : "")\(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed). Counts are not normalized for weekly plan size.",
                            norwegian: "Registrert endring: fullført \(trend.latest.pastCompleted - trend.previous.pastCompleted >= 0 ? "+" : "")\(trend.latest.pastCompleted - trend.previous.pastCompleted), hoppet over \(trend.latest.pastSkipped - trend.previous.pastSkipped >= 0 ? "+" : "")\(trend.latest.pastSkipped - trend.previous.pastSkipped), uavklart \(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed >= 0 ? "+" : "")\(trend.latest.pastUnreviewed - trend.previous.pastUnreviewed). Antall er ikke justert for ulikt antall planlagte økter."
                        ))
                        .font(.caption2)
                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if report.pastDated > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "Past workouts accounted for: \(report.pastConfirmed) of \(report.pastDated) · includes completed and skipped.",
                                norwegian: "Tidligere økter avklart: \(report.pastConfirmed) av \(report.pastDated) · inkluderer fullførte og hoppet over."
                            ),
                            systemImage: "checkmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(ATHLTHLocalization.choose(
                        english: "\(report.skipped) skipped · \(report.unknownDate) without plan dates. Today's unfinished sessions are still upcoming.",
                        norwegian: "\(report.skipped) hoppet over · \(report.unknownDate) uten plandato. Dagens ufullførte økter regnes fortsatt som kommende."
                    ))
                    .font(.caption2)
                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                    if report.needsReview > 0 {
                        Label(
                            ATHLTHLocalization.choose(
                                english: "\(report.needsReview) past sessions have no confirmed result. Review these days to decide whether a recording needs linking or the plan needs updating.",
                                norwegian: "\(report.needsReview) tidligere økter mangler bekreftet resultat. Gå gjennom dagene for å se om en registrering må kobles eller planen bør oppdateres."
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(ATHLTHPlanDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(Array(relevant.prefix(
                        showsAll ? relevant.count : 4
                    ))) { week in
                        Button {
                            onSelect(week.id, week.preferredReviewDayID)
                        } label: {
                            HStack(spacing: 12) {
                                Text(ATHLTHLocalization.choose(
                                    english: "W\(week.number)",
                                    norwegian: "U\(week.number)"
                                ))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(ATHLTHPlanDesign.ink)
                                .frame(width: 40, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ATHLTHLocalization.choose(
                                        english: "\(week.completed) completed · \(week.upcoming) upcoming",
                                        norwegian: "\(week.completed) fullført · \(week.upcoming) kommende"
                                    ))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(ATHLTHPlanDesign.ink)

                                    if week.needsReview > 0 {
                                        Text(ATHLTHLocalization.choose(
                                            english: "\(week.needsReview) to review · open related day",
                                            norwegian: "\(week.needsReview) til gjennomgang · åpne dagen"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    } else if week.pastSkipped > 0 {
                                        Text(ATHLTHLocalization.choose(
                                            english: "\(week.pastSkipped) past skipped · open related day",
                                            norwegian: "\(week.pastSkipped) tidligere hoppet over · åpne dagen"
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(ATHLTHTheme.accentDeep)
                                    } else {
                                        Text(ATHLTHLocalization.choose(
                                            english: "\(week.skipped) skipped · \(week.unknownDate) undated",
                                            norwegian: "\(week.skipped) hoppet over · \(week.unknownDate) uten dato"
                                        ))
                                        .font(.caption2)
                                        .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(ATHLTHLocalization.choose(
                            english: "Open this week or a past workout day to review, without changing the plan.",
                            norwegian: "Åpne uken eller en tidligere økt til gjennomgang, uten å endre planen."
                        ))
                    }

                    if relevant.count > 4 {
                        Button {
                            showsAll.toggle()
                        } label: {
                            Label(
                                showsAll
                                    ? ATHLTHLocalization.choose(
                                        english: "Show fewer weeks",
                                        norwegian: "Vis færre uker"
                                    )
                                    : ATHLTHLocalization.choose(
                                        english: "Show all \(relevant.count) weeks",
                                        norwegian: "Vis alle \(relevant.count) uker"
                                    ),
                                systemImage: showsAll
                                    ? "chevron.up" : "chevron.down"
                            )
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            let latestPlan = session.trainingPlan(withID: plan.id) ?? plan
            previewEfforts = ATHLTHPlanWeeklyFollowThrough.savedEfforts(plan: latestPlan)
        }
    }

    /// Show a calendar date instead of ambiguous "day 1–7" labels.
    /// The fallback remains stable for plans without a valid start date.
    private func moveDayLabel(
        _ dayIndex: Int, weekID: UUID, plan: TrainingPlan
    ) -> String {
        guard (1...7).contains(dayIndex),
              let start = plan.startDate,
              let weekOffset = plan.weeks.firstIndex(where: { $0.id == weekID }),
              let date = Calendar.current.date(
                  byAdding: .day,
                  value: weekOffset * 7 + dayIndex - 1,
                  to: Calendar.current.startOfDay(for: start)
              ) else {
            return ATHLTHLocalization.choose(
                english: "Day \(dayIndex)", norwegian: "Dag \(dayIndex)"
            )
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func metric(_ number: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(number)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ATHLTHPlanDesign.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(ATHLTHPlanDesign.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
    private func updateEffort(
        _ effort: ATHLTHPlanWeeklyFollowThrough.PlannedEffort?,
        for sessionID: UUID, plan: TrainingPlan
    ) {
        if let effort {
            previewEfforts[sessionID] = effort
        } else {
            previewEfforts.removeValue(forKey: sessionID)
        }
        ATHLTHPlanWeeklyFollowThrough.saveEfforts(previewEfforts, plan: plan)
    }

    private func clearEfforts(plan: TrainingPlan) {
        previewEfforts.removeAll()
        ATHLTHPlanWeeklyFollowThrough.saveEfforts(previewEfforts, plan: plan)
    }

}
