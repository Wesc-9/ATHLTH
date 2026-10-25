import SwiftUI

/// The light "I dag" surface is deliberately separate from workout recording.
/// Plans feed this view, while launching still goes through ATHLTHTrainView.
struct ATHLTHTrainTodayPremiumView: View {
    @EnvironmentObject private var social: SocialStore
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var goalStore: GoalStore
    @ObservedObject var workoutCatalog: WorkoutTemplateCatalogStore

    let plan: TrainingPlan?
    let sessions: [PlannedSession]
    let completedIDs: Set<UUID>
    let healthCompletedIDs: Set<UUID>
    let completionFraction: Double
    let planPosition: String
    let hasActiveWorkout: Bool
    let activeWorkoutKind: WorkoutKind?
    /// Live recorder-owned content replaces the scheduled action while active.
    let activeWorkoutCard: AnyView?
    let hasRecordedWorkoutToday: Bool
    /// Already filtered for a reliable, recent HealthKit baseline by the parent.
    let todaysReadiness: RecoveryReadinessSummary?
    let onChooseSuggestedWorkout: (WorkoutTemplateCatalogEntry) -> Void
    let onOpenPlan: () -> Void
    let onCreatePlan: () -> Void
    let onOpenLibrary: () -> Void
    let onStartWorkout: (PlannedSession, Bool) -> Void
    let onWorkoutDetails: (PlannedSession, Bool) -> Void
    /// Changes only the selected unfinished workout after explicit approval.
    let onAcceptAlternative: (
        PlannedSession, ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    ) -> Void
    let onUndoAlternative: (PlannedSession) -> Void

    @State private var reportedEnergy: Int?
    @State private var reportedStress: Int?
    @State private var reportedSoreness: Int?
    @State private var reportedMuscles: [String: RecoverySorenessLevel] = [:]
    @State private var pendingSwap: PendingSwap?

    private struct PendingSwap {
        let workout: PlannedSession
        let suggestion: ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    }

    private var selfReportedSignals: ATHLTHDailyWorkoutAlternativeAdvisor.Signals {
        .init(energy: reportedEnergy, stress: reportedStress,
              overallSoreness: reportedSoreness,
              muscleRatings: reportedMuscles, readiness: todaysReadiness)
    }

    private func reloadCheckIn() {
        let current = RecoverySorenessStore()
        reportedEnergy = current.todayEnergy
        reportedStress = current.todayStress
        reportedSoreness = current.todayOverallSoreness
        reportedMuscles = current.todayRatings
    }
    let onQuickTrain: (WorkoutKind) -> Void
    let onQuickCycling: () -> Void
    let onQuickCustom: (CustomQuickWorkoutActivity) -> Void
    let onGhostRace: () -> Void

    @State private var quickActivityTapCounts: [String: Int] = [:]
    @State private var temporarilyFeaturedGoalID: UUID?


    private let ink = ATHLTHPlanDesign.ink
    private let muted = ATHLTHPlanDesign.secondaryInk
    private let champagne = ATHLTHPlanDesign.accentInk
    private let hairline = ATHLTHPlanDesign.warmDivider

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            // A current program is context, not the hero: display one quiet,
            // factual entry above the primary session only when it exists.
            if let plan {
                activePlanSection(plan)
            }
            todayAgendaStrip
            // A running recording takes priority over a planned-start card.
            if hasActiveWorkout, let activeWorkoutCard {
                activeWorkoutCard
            } else if let plan {
                let scheduled = sessions.filter { !$0.isExplicitRestDay }
                if scheduled.isEmpty && sessions.contains(where: \.isExplicitRestDay) {
                    restDayCard
                    if let swapped = sessions.first(where: {
                        $0.isExplicitRestDay && $0.dailyAlternativeOriginal != nil
                    }) {
                        undoAlternativeRow(swapped)
                    }
                } else if !scheduled.isEmpty &&
                            scheduled.allSatisfy({ completedIDs.contains($0.id) }) {
                    completedTodayCard(plan)
                } else if let workout = primaryWorkout {
                    workoutCard(workout, plan: plan)
                } else {
                    openDayOverview(hasPlan: true)
                }
            } else {
                openDayOverview(hasPlan: false)
            }

            // Quick Train is always directly below the principal workout,
            // using precisely the same launch callbacks as before.
            quickTrainSection
            activeGoalSection
            dailyFocusSection
            suggestedWorkoutSection
            ghostRaceSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            reloadCheckIn()
            await workoutCatalog.refresh()
        }
        .task(id: session.profile.userID) {
            quickActivityTapCounts =
                UserDefaults.standard.dictionary(forKey: quickActivityStorageKey)
                    as? [String: Int] ?? [:]
            temporarilyFeaturedGoalID = nil
        }
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("athlth.dailyCheckInDidUpdate")
        )) { _ in
            reloadCheckIn()
        }
        .confirmationDialog(
            tr("Swap today's workout?", "Bytte dagens økt?"),
            isPresented: Binding(
                get: { pendingSwap != nil },
                set: { if !$0 { pendingSwap = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingSwap {
                Button(tr("Use", "Bruk") + " " + pendingSwap.suggestion.title) {
                    onAcceptAlternative(pendingSwap.workout, pendingSwap.suggestion)
                    self.pendingSwap = nil
                }
            }
            Button(tr("Cancel", "Avbryt"), role: .cancel) {
                pendingSwap = nil
            }
        } message: {
            Text(tr(
                "Only this unfinished workout changes. The original stays available to restore.",
                "Kun denne ufullførte økten endres. Du kan når som helst gjenopprette den opprinnelige økten."
            ))
        }
    }

    // The factual first-screen agenda: scheduled sessions are distinct from
    // HealthKit recordings, and a day without a plan is not labelled a rest day.
    private var todayAgendaStrip: some View {
        let planned = sessions.filter { !$0.isExplicitRestDay }
        let done = planned.filter { completedIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("TODAY'S OVERVIEW", "DAGENS OVERSIKT"))
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(champagne)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                if hasActiveWorkout {
                    Label(
                        tr("Workout active", "Aktiv økt"),
                        systemImage: "waveform.path"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                } else if planned.isEmpty && hasRecordedWorkoutToday {
                    Label(
                        tr("Workout recorded", "Økt registrert"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ATHLTHTheme.vitality)
                }
            }

            if !planned.isEmpty {
                HStack(spacing: 7) {
                    ForEach(planned) { workout in
                        Capsule()
                            .fill(
                                completedIDs.contains(workout.id)
                                    ? ATHLTHTheme.vitality
                                    : champagne.opacity(0.65)
                            )
                            .frame(height: 5)
                    }
                }
                Text(
                    "\(done) / \(planned.count) " +
                    tr("planned workouts complete", "planlagte økter fullført")
                )
                .font(.caption)
                .foregroundStyle(muted)
            } else {
                Text(sessions.contains(where: \.isExplicitRestDay)
                    ? tr("Recovery is scheduled today.", "I dag er det planlagt restitusjon.")
                    : tr("No scheduled workout. Choose a quick session or plan ahead.",
                         "Ingen planlagt økt. Start en rask økt eller planlegg fremover."))
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    private var futurePlanningAction: some View {
        Button {
            if plan != nil {
                onOpenPlan()
            } else {
                onCreatePlan()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 33)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Plan your next workouts", "Planlegg kommende økter"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Build a week, choose a day, or reuse your workouts",
                        "Bygg en uke, velg en dag eller gjenbruk lagrede økter"
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .padding(16)
            .premiumTrainSurface(line: hairline)
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr(
            "Open training plan studio",
            "Åpne treningsplanstudio"
        ))
    }

    private var primaryWorkout: PlannedSession? {
        let workouts = sessions.filter { !$0.isExplicitRestDay }
        return workouts.first { !completedIDs.contains($0.id) } ?? workouts.first
    }

    /// Show an actual alternative and its reason immediately after the
    /// workout. The athlete never has to open a generic 'Adjust' tile to
    /// discover the recommendation.
    /// All actionable alternatives are visible without an intermediary tile,
    /// dropdown or navigation. The two safest choices for each signal are
    /// shown directly beneath the primary workout action.
    private func alternativeRecommendationCard(
        for workout: PlannedSession,
        suggestion: ATHLTHDailyWorkoutAlternativeAdvisor.Suggestion
    ) -> some View {
        let alternatives = Array(ATHLTHDailyWorkoutAlternativeAdvisor.suggestions(
            for: workout, signals: selfReportedSignals).prefix(2))

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Text(tr("ATHLTH SUGGESTS", "ATHLTH FORESLÅR"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(ATHLTHPlanDesign.accentInk)
                Spacer()
            }

            Text(suggestion.reason)
                .font(.caption)
                .foregroundStyle(ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(alternatives) { option in
                    Button {
                        pendingSwap = PendingSwap(
                            workout: workout, suggestion: option)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.choice.symbol)
                                .font(.caption.weight(.semibold))
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .foregroundStyle(
                            option.id == suggestion.id
                                ? Color.white : ATHLTHPlanDesign.accentInk)
                        .background(
                            option.id == suggestion.id
                                ? ATHLTHPlanDesign.accentInk
                                : Color.white.opacity(0.90),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    option.id == suggestion.id
                                        ? Color.clear : ATHLTHPlanDesign.outline,
                                    lineWidth: 0.8)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr(
                        "Review a replacement for today's workout",
                        "Bekreft et alternativ til dagens økt"))
                }
            }

            Text(tr("Your plan changes only after confirmation.",
                    "Planen endres først når du bekrefter."))
                .font(.system(size: 10))
                .foregroundStyle(muted)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [ATHLTHPlanDesign.selectedSurface,
                         ATHLTHPlanDesign.warmSurface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(ATHLTHPlanDesign.outline, lineWidth: 0.7)
        }
    }

    private func undoAlternativeRow(_ workout: PlannedSession) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ATHLTHPlanDesign.accentInk)
            Text(tr("Today's alternative selected",
                    "Dagens alternative økt er valgt"))
                .font(.caption.weight(.medium))
                .foregroundStyle(ink)
            Spacer()
            Button(tr("Undo", "Angre")) {
                onUndoAlternative(workout)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ATHLTHPlanDesign.accentInk)
        }
        .padding(12)
        .background(ATHLTHPlanDesign.selectedSurface,
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private var restDayCard: some View {
        Button(action: onOpenPlan) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(ATHLTHTheme.recoveryBlue)
                    .frame(width: 50, height: 50)
                    .background(ATHLTHTheme.recoveryBlueSoft,
                                in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("REST DAY", "HVILEDAG"))
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                    Text(tr("Recovery is on the schedule", "Restitusjon er planlagt"))
                        .font(.headline)
                    Text(tr(
                        "You have no workout to complete today. View the day in your plan.",
                        "Du har ingen treningsøkt å fullføre i dag. Se dagen i treningsplanen."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(muted)
            }
            .foregroundStyle(ink)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // A full date on regular widths, a shorter date where labels need room.
    private func todayDateLabel(color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .fixedSize(horizontal: true, vertical: false)
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .lineLimit(1)
        .accessibilityLabel(
            Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        )
    }

    private struct HeroPhase: Identifiable {
        let phase: WorkoutPhaseKind
        let minutes: Int?
        var id: String { phase.rawValue }
    }

    /// Display only phases actually present in the workout. This must never
    /// invent warmup, cooldown, reps or recovery based on a decorative mockup.
    private func heroPhases(for workout: PlannedSession) -> [HeroPhase] {
        let blocks = ATHLTHUnifiedWorkout.editorBlocks(from: workout)
        return WorkoutPhaseKind.allCases.compactMap { phase in
            let matching = blocks.filter { $0.resolvedPhase == phase }
            guard !matching.isEmpty else { return nil }
            let seconds = matching.compactMap(\.durationSeconds)
                .filter { $0 > 0 }
                .reduce(0.0, +)
            let minutes = seconds > 0
                ? max(1, Int((seconds / 60).rounded(.up)))
                : (blocks.count == matching.count ? workout.durationMinutes : nil)
            return HeroPhase(phase: phase, minutes: minutes)
        }
    }

    private func workoutCard(
        _ workout: PlannedSession, plan: TrainingPlan
    ) -> some View {
        let finished = completedIDs.contains(workout.id)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: -54) {
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Image(workoutImage(for: workout.kind))
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: 368)
                            .clipped()
                    }
                    .frame(height: 368)

                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.05), location: 0),
                            .init(color: .black.opacity(0.05), location: 0.36),
                            .init(color: .black.opacity(0.62), location: 0.96)
                        ], startPoint: .top, endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(Date.now.formatted(
                            .dateTime.weekday(.wide).day().month(.wide)
                        ).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2.0)
                            .foregroundStyle(.white.opacity(0.91))

                        Text(workout.title)
                            .font(.system(size: 43, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.70)
                            .shadow(color: .black.opacity(0.20), radius: 7)

                        HStack(spacing: 15) {
                            heroMeta("clock", workout.durationMinutes.map {
                                "\($0) min"
                            } ?? tr("Flexible", "Fleksibel"))
                            heroMeta(workout.kind.systemImage, workout.kind.title)
                            if let intensity = heroIntensity(workout) {
                                heroMeta("chart.bar.fill", intensity)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                        // The light floating control plate overlaps the photo.
                        Spacer().frame(height: 93)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 20)
                }
                .frame(height: 368)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 15) {
                    Button {
                        onWorkoutDetails(
                            workout, healthCompletedIDs.contains(workout.id))
                    } label: {
                        heroTimeline(for: workout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr(
                        "Open all workout steps", "Åpne alle øktdelene"
                    ))

                    HStack(spacing: 12) {
                        Button {
                            if hasActiveWorkout || finished {
                                onWorkoutDetails(
                                    workout, healthCompletedIDs.contains(workout.id))
                            } else {
                                onStartWorkout(
                                    workout, healthCompletedIDs.contains(workout.id))
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Spacer()
                                Image(systemName: hasActiveWorkout || finished
                                    ? "arrow.up.right" : "play.fill")
                                Text(finished
                                     ? tr("View workout", "Se økten")
                                     : hasActiveWorkout
                                     ? tr("View planned workout", "Se planlagt økt")
                                     : tr("Start workout", "Start økt"))
                                Spacer()
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minHeight: 58)
                            .background(ink,
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                onWorkoutDetails(workout,
                                    healthCompletedIDs.contains(workout.id))
                            } label: {
                                Label(tr("View workout", "Se økten"),
                                      systemImage: "list.bullet")
                            }
                            Button(action: onOpenPlan) {
                                Label(tr("Training plan", "Treningsplan"),
                                      systemImage: "calendar")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(ink)
                                .frame(width: 58, height: 58)
                                .background(ATHLTHPlanDesign.warmSurface,
                                            in: Circle())
                                .overlay {
                                    Circle().strokeBorder(
                                        hairline.opacity(0.7), lineWidth: 0.8)
                                }
                        }
                        .accessibilityLabel(tr(
                            "Workout options", "Øktvalg"
                        ))
                    }
                }
                .padding(16)
                .background(.white,
                            in: RoundedRectangle(cornerRadius: 22))
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(hairline.opacity(0.65), lineWidth: 0.7)
                }
                .shadow(color: ink.opacity(0.12), radius: 22, y: 10)
                .padding(.horizontal, 13)
            }

            // All alternatives and secondary sessions remain available,
            // rather than being hidden or silently replaced by the redesign.
            if workout.dailyAlternativeOriginal != nil {
                undoAlternativeRow(workout)
            } else if !finished && !hasActiveWorkout,
                      let suggestion = ATHLTHDailyWorkoutAlternativeAdvisor
                        .suggestions(for: workout,
                                     signals: selfReportedSignals).first {
                alternativeRecommendationCard(for: workout, suggestion: suggestion)
            }

            if sessions.filter({ !$0.isExplicitRestDay && $0.id != workout.id }).count > 0 {
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("ALSO TODAY", "OGSÅ I DAG"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(muted)
                    ForEach(sessions.filter { !$0.isExplicitRestDay && $0.id != workout.id }) { extra in
                        Button {
                            onWorkoutDetails(extra,
                                healthCompletedIDs.contains(extra.id))
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: extra.kind.systemImage)
                                Text(extra.title).lineLimit(1)
                                Spacer()
                                if completedIDs.contains(extra.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ink)
                            .padding(13)
                            .background(.white,
                                in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func heroMeta(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            Text(value)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
    }

    private func heroIntensity(_ workout: PlannedSession) -> String? {
        if let zone = workout.resolvedWorkoutBlocks
            .compactMap(\.targetHeartRateZone).first {
            return tr("Zone", "Sone") + " \(zone)"
        }
        return nil
    }

    @ViewBuilder
    private func heroTimeline(for workout: PlannedSession) -> some View {
        let phases = heroPhases(for: workout)
        if phases.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet")
                Text(tr("View workout details", "Se øktens innhold"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(ink)
            .frame(minHeight: 43)
        } else {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(ink)
                    .frame(width: 24)
                HStack(alignment: .top, spacing: 4) {
                    ForEach(phases) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 0) {
                                Circle()
                                    .fill(ATHLTHPlanDesign.ink.opacity(0.55))
                                    .frame(width: 8, height: 8)
                                Rectangle()
                                    .fill(hairline)
                                    .frame(height: 2)
                            }
                            Text(item.phase.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if let minutes = item.minutes {
                                Text("\(minutes) min")
                                    .font(.system(size: 11))
                                    .foregroundStyle(muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(muted)
            }
            .foregroundStyle(ink)
            .frame(minHeight: 58)
        }
    }

    /// A plan-free day is not automatically a prescribed rest day. Keep
    /// this overview informational and allow the original Quick Train actions.
    private func openDayOverview(hasPlan: Bool) -> some View {
        let status = TrainTodayOverviewPolicy.status(
            hasPlan: hasPlan,
            hasRecordedWorkoutToday: hasRecordedWorkoutToday
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(champagne)
                Text(tr("YOUR DAY", "DIN DAG"))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(muted)
                Spacer(minLength: 4)
                if status == .trainedToday {
                    Label(
                        tr("Recorded", "Registrert"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(red: 0.19, green: 0.44, blue: 0.36))
                    .lineLimit(1)
                }
                todayDateLabel(color: muted)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(dayHeadline(for: status))
                    .font(.system(size: 24, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dayDescription(for: status))
                    .font(.subheadline)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle()
                .fill(hairline.opacity(0.75))
                .frame(height: 0.7)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("TODAY'S PLAN", "DAGENS PLAN"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(muted)
                    Text(hasPlan
                         ? tr("No scheduled workout", "Ingen planlagt økt")
                         : tr("No active training plan", "Ingen aktiv treningsplan"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ink)
                }
                Spacer(minLength: 0)
                if !hasPlan {
                    Button(action: onCreatePlan) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                            .frame(width: 34, height: 34)
                            .background(
                                Color(red: 0.96, green: 0.94, blue: 0.91),
                                in: Circle()
                            )
                            .overlay {
                                Circle()
                                    .stroke(hairline.opacity(0.8), lineWidth: 0.8)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        tr("Create training plan", "Opprett treningsplan")
                    )
                    .accessibilityHint(
                        tr("Open training plan builder", "Åpne treningsplanbyggeren")
                    )
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: todaysReadiness?.state.systemImage ?? "heart.text.square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(champagne)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("RECOVERY", "RESTITUSJON"))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(muted)

                    if let todaysReadiness, let score = todaysReadiness.score {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(readinessTitle(todaysReadiness.state))
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 4)
                            Text("\(score)/100")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(ink)
                        Text(tr(
                            "Based on recent authorized health data, not a prescribed rest day.",
                            "Basert på oppdaterte helsedata – ikke en pålagt hviledag."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(tr(
                            "Not enough up-to-date health data for today's assessment.",
                            "Ikke nok oppdaterte helsedata til å vurdere dagsformen."
                        ))
                        .font(.caption)
                        .foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    private func dayHeadline(
        for status: TrainTodayOverviewPolicy.Status
    ) -> String {
        switch status {
        case .trainedToday:
            return tr("You've trained today", "Du har trent i dag")
        case .noWorkoutInPlan:
            return tr("A flexible training day", "En åpen treningsdag")
        case .noActivePlan:
            return tr("Your day, your choice", "Dagen er din")
        }
    }

    private func dayDescription(
        for status: TrainTodayOverviewPolicy.Status
    ) -> String {
        switch status {
        case .trainedToday:
            return tr(
                "An activity has been recorded today, even though none was scheduled.",
                "En aktivitet er registrert i dag, selv om ingen økt var planlagt."
            )
        case .noWorkoutInPlan:
            return tr(
                "There is no workout in your plan today. You can rest or choose an activity.",
                "Det ligger ingen økt i planen i dag. Du kan hvile eller velge en aktivitet."
            )
        case .noActivePlan:
            return tr(
                "Nothing is scheduled. Rest, move freely, or build a training plan.",
                "Ingenting er planlagt. Hvil, beveg deg fritt eller lag en treningsplan."
            )
        }
    }

    private func readinessTitle(_ state: RecoveryReadinessState) -> String {
        switch state {
        case .ready: return tr("Ready for activity", "Klar for aktivitet")
        case .balanced: return tr("Balanced", "Balansert")
        case .takeItEasy: return tr("Take it a little easier", "Ta det litt roligere")
        case .recover: return tr("Consider recovery", "Vurder restitusjon")
        case .buildingBaseline: return tr("Building baseline", "Bygger grunnlag")
        }
    }

    // Curated and published recipes share a single source, so useful strength
    // suggestions remain available offline as well as online.
    private var suggestedWorkouts: [WorkoutTemplateCatalogEntry] {
        return TrainWorkoutSuggestionPolicy.pick(
            workoutCatalog.entries, preferredKind: primaryWorkout?.kind
        )
    }

    @ViewBuilder
    private var suggestedWorkoutSection: some View {
        let suggestions = suggestedWorkouts
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("Popular from the library", "Populært fra biblioteket"))
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                    Spacer(minLength: 6)
                    Button(action: onOpenLibrary) {
                        HStack(spacing: 5) {
                            Text(tr("See all", "Se alle"))
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(muted)
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(suggestions.prefix(2)) { entry in
                        Button {
                            onChooseSuggestedWorkout(entry)
                        } label: {
                            HStack(spacing: 8) {
                                Image(suggestionImage(for: entry))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 65, height: 76)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(suggestionSubtitle(entry))
                                        .font(.system(size: 11))
                                        .foregroundStyle(muted)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(muted)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, minHeight: 90,
                                   alignment: .leading)
                            .background(.white,
                                in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(hairline.opacity(0.8),
                                                  lineWidth: 0.65)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func suggestionImage(
        for entry: WorkoutTemplateCatalogEntry
    ) -> String {
        switch entry.category.lowercased() {
        case "strength", "gym": return "StrengthQuickHero"
        case "walking", "hiking": return "GoalWalking"
        case "recovery", "mobility", "yoga": return "GoalRecovery"
        case "running", "cardio", "interval": return "GoalRunning"
        default: return "TrainHero"
        }
    }

    private func suggestionSubtitle(_ entry: WorkoutTemplateCatalogEntry) -> String {
        var parts = [entry.categoryTitle]
        if let minutes = entry.estimatedDurationMinutes, minutes > 0 {
            parts.append("\(minutes) min")
        }
        parts.append(tr(
            "\(entry.blocks.count) steps",
            "\(entry.blocks.count) steg"
        ))
        return parts.joined(separator: " · ")
    }

    // Shortcuts reuse the existing training library. No new recommendation
    // engine or Quick Train changes are needed for this navigation improvement.
    private func completedTodayCard(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(champagne)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Today's training is done", "Dagens trening er fullført"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(tr(
                        "Your planned sessions are complete.",
                        "De planlagte øktene dine er gjennomført."
                    ))
                    .font(.caption)
                    .foregroundStyle(muted)
                    todayDateLabel(color: muted)
                }
                Spacer(minLength: 0)
            }
            Button(action: onOpenPlan) {
                Label(tr("View your plan", "Se treningsplanen"),
                      systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .premiumTrainSurface(line: hairline)
    }

    // Click history reflects intentional entry choices, not completed
    // workout statistics. Ordering is per ATHLTH account on this device.
    private enum QuickActivity: String, CaseIterable, Identifiable {
        case running, walking, strength, cycling, yoga, custom
        var id: String { rawValue }

        var image: String {
            switch self {
            case .running: return "GoalRunning"
            case .walking: return "GoalWalking"
            case .strength: return "StrengthQuickHero"
            case .cycling: return "TrainHero"
            case .yoga: return "GoalRelax"
            case .custom: return "GoalAdventure"
            }
        }

        var icon: String {
            switch self {
            case .running: return "figure.run"
            case .walking: return "figure.walk"
            case .strength: return "dumbbell.fill"
            case .cycling: return "bicycle"
            case .yoga: return "figure.yoga"
            case .custom: return "slider.horizontal.3"
            }
        }

        var title: String {
            switch self {
            case .running:
                return ATHLTHLocalization.choose(english: "Run", norwegian: "Løping")
            case .walking:
                return ATHLTHLocalization.choose(english: "Walk", norwegian: "Gå")
            case .strength:
                return ATHLTHLocalization.choose(english: "Strength", norwegian: "Styrke")
            case .cycling:
                return ATHLTHLocalization.choose(english: "Cycling", norwegian: "Sykling")
            case .yoga: return "Yoga"
            case .custom:
                return ATHLTHLocalization.choose(
                    english: "Custom", norwegian: "Egendefinert"
                )
            }
        }
    }

    private var quickActivityStorageKey: String {
        "athlth.train.today.quickTaps." + String(describing: session.profile.userID)
    }

    private var sortedQuickActivities: [QuickActivity] {
        let defaults = QuickActivity.allCases
        return defaults.sorted { first, second in
            let firstCount = quickActivityTapCounts[first.rawValue, default: 0]
            let secondCount = quickActivityTapCounts[second.rawValue, default: 0]
            if firstCount != secondCount { return firstCount > secondCount }
            return (defaults.firstIndex(of: first) ?? 0) <
                (defaults.firstIndex(of: second) ?? 0)
        }
    }

    private func recordQuickActivityTap(_ activity: QuickActivity) {
        var counts = quickActivityTapCounts
        counts[activity.rawValue] = min(
            counts[activity.rawValue, default: 0] + 1, 100_000
        )
        quickActivityTapCounts = counts
        UserDefaults.standard.set(counts, forKey: quickActivityStorageKey)
    }

    private func openQuickActivity(_ activity: QuickActivity) {
        recordQuickActivityTap(activity)
        social.quickTrainFriendIDs.removeAll()
        social.discardPreparedQuickTrainFriends()
        switch activity {
        case .running: onQuickTrain(.running)
        case .walking: onQuickTrain(.walking)
        case .strength: onQuickTrain(.strength)
        case .cycling: onQuickCycling()
        case .yoga: onQuickCustom(.yoga)
        case .custom: onQuickCustom(.other)
        }
    }

    /// The account's saved primary goal remains unchanged. Spotlighting
    /// another goal is a reversible display-only choice for this visit.
    private var primaryTrainGoal: ATHLTHGoal? {
        if let primary = goalStore.primaryGoal, primary.status == .active {
            return primary
        }
        return goalStore.activeGoals.first { $0.status == .active }
    }

    private var goalContextKind: WorkoutKind? {
        if hasActiveWorkout { return activeWorkoutKind }
        guard let workout = primaryWorkout,
              !completedIDs.contains(workout.id),
              !workout.isExplicitRestDay
        else { return nil }
        return workout.kind
    }

    private var goalRecommendationReason: String {
        switch goalContextKind {
        case .running:
            return tr("Matches today's run", "Passer til dagens løpeøkt")
        case .walking:
            return tr("Matches today's walk", "Passer til dagens gåøkt")
        case .strength:
            return tr("Matches today's strength training", "Passer til dagens styrkeøkt")
        case .mobility:
            return tr("Matches today's mobility work", "Passer til dagens bevegelighetstrening")
        case .recovery:
            return tr("Matches today's recovery", "Passer til dagens restitusjon")
        case .custom, .none:
            return tr("Relevant to today's workout", "Relevant for dagens trening")
        }
    }

    private var relevantGoalSuggestion: ATHLTHGoal? {
        ATHLTHTrainGoalPriority.recommend(
            goals: goalStore.activeGoals,
            primary: primaryTrainGoal,
            activity: goalContextKind,
            activePlanID: plan?.id
        )
    }

    private var visibleTrainGoal: ATHLTHGoal? {
        if let suggested = relevantGoalSuggestion,
           temporarilyFeaturedGoalID == suggested.id {
            return suggested
        }
        return primaryTrainGoal
    }

    @ViewBuilder
    private var activeGoalSection: some View {
        if let goal = visibleTrainGoal {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink {
                    GoalDetailView(goalID: goal.id)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: goal.category.systemImage)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(champagne)
                            .frame(width: 41, height: 41)
                            .background(ATHLTHPlanDesign.warmSurface,
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(temporarilyFeaturedGoalID == goal.id &&
                                 relevantGoalSuggestion?.id == goal.id
                                 ? tr("TODAY'S GOAL", "MÅL FOR I DAG")
                                 : tr("ACTIVE GOAL", "AKTIVT MÅL"))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.1)
                                .foregroundStyle(muted)
                            Text(goal.title)
                                .font(.system(size: 18, weight: .regular, design: .serif))
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if !goal.milestones.isEmpty {
                                Text(tr(
                                    "\(goal.completedMilestones) of \(goal.milestones.count) milestones",
                                    "\(goal.completedMilestones) av \(goal.milestones.count) delmål"
                                ))
                                .font(.caption)
                                .foregroundStyle(muted)
                            } else if let deadline = goal.deadline {
                                Text(deadline.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(muted)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Active goal", "Aktivt mål") + ": " + goal.title)

                if let suggested = relevantGoalSuggestion {
                    Rectangle()
                        .fill(hairline.opacity(0.72))
                        .frame(height: 1)

                    HStack(spacing: 11) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(champagne)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("RELEVANT TODAY", "RELEVANT I DAG"))
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.9)
                                .foregroundStyle(champagne)
                            Text(temporarilyFeaturedGoalID == suggested.id
                                 ? tr("Your original main goal is unchanged.",
                                      "Det opprinnelige hovedmålet er uendret.")
                                 : suggested.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(ink)
                                .lineLimit(2)
                            if temporarilyFeaturedGoalID != suggested.id {
                                Text(goalRecommendationReason)
                                    .font(.caption2)
                                    .foregroundStyle(muted)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                temporarilyFeaturedGoalID =
                                    temporarilyFeaturedGoalID == suggested.id
                                        ? nil : suggested.id
                            }
                        } label: {
                            Text(temporarilyFeaturedGoalID == suggested.id
                                 ? tr("Main goal", "Hovedmål")
                                 : tr("Show", "Vis"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ink)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            temporarilyFeaturedGoalID == suggested.id
                                ? tr("Show my main goal", "Vis hovedmålet mitt")
                                : tr("Temporarily show suggested goal",
                                     "Vis foreslått mål midlertidig")
                        )
                    }
                }
            }
            .padding(16)
            .premiumTrainSurface(line: hairline)
        } else {
            NavigationLink {
                GoalsHubView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "target")
                        .font(.system(size: 20))
                        .foregroundStyle(champagne)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("ACTIVE GOAL", "AKTIVT MÅL"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(muted)
                        Text(tr("Choose something to train toward",
                                "Velg et mål å trene mot"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(ink)
                }
                .padding(16)
                .premiumTrainSurface(line: hairline)
            }
            .buttonStyle(.plain)
        }
    }

    private var dailyFocusSection: some View {
        let workout = primaryWorkout
        let focusTitle: String
        let focusBody: String
        let focusIcon: String

        if hasActiveWorkout {
            focusTitle = tr("Stay with your session", "Fortsett økten")
            focusBody = tr(
                "Your workout is being recorded. Resume it from the live card above.",
                "Økten registreres. Åpne den igjen fra livekortet over."
            )
            focusIcon = "waveform.path"
        } else if let workout, !completedIDs.contains(workout.id) {
            focusTitle = workout.title
            focusBody = workout.durationMinutes.map {
                tr("Planned duration: \($0) min. See workout details before you start.",
                   "Planlagt varighet: \($0) min. Se øktdetaljene før start.")
            } ?? tr("Review the planned steps before starting.",
                    "Se gjennom øktens deler før du starter.")
            focusIcon = workout.kind.systemImage
        } else if hasRecordedWorkoutToday {
            focusTitle = tr("Training recorded", "Trening registrert")
            focusBody = tr(
                "Today's workout is in your history. Plan or start another only if you want.",
                "Dagens økt ligger i historikken. Planlegg eller start en ny hvis du ønsker."
            )
            focusIcon = "checkmark.circle"
        } else if sessions.contains(where: \.isExplicitRestDay) {
            focusTitle = tr("Scheduled recovery", "Planlagt restitusjon")
            focusBody = tr("Your plan lists recovery today.",
                           "Treningsplanen har restitusjon i dag.")
            focusIcon = "leaf"
        } else {
            focusTitle = tr("Choose your training", "Velg dagens trening")
            focusBody = tr(
                "Start a familiar activity above or explore an exercise from the library.",
                "Start en kjent aktivitet over, eller utforsk en økt fra biblioteket."
            )
            focusIcon = "sparkles"
        }

        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: focusIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(champagne)
                .frame(width: 36, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("TODAY'S FOCUS", "DAGENS FOKUS"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(muted)
                Text(focusTitle)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                Text(focusBody)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .premiumTrainSurface(line: hairline)
    }

    private var quickTrainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(champagne)
                Text(tr("Start a workout", "Start en økt"))
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                Spacer(minLength: 4)
                Button {
                    if plan == nil {
                        onCreatePlan()
                    } else {
                        onOpenPlan()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.plus")
                        Text(tr("Plan", "Planlegg"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(ATHLTHPlanDesign.warmSurface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Plan a workout", "Planlegg en økt"))
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 9),
                    GridItem(.flexible(), spacing: 9)
                ],
                spacing: 9
            ) {
                ForEach(sortedQuickActivities) { activity in
                    quickPhotoChoice(activity)
                }
            }
        }
    }

    private func quickPhotoChoice(_ activity: QuickActivity) -> some View {
        Button {
            openQuickActivity(activity)
        } label: {
            ZStack(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Image(activity.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: 92)
                        .clipped()
                }
                .frame(height: 92)

                LinearGradient(
                    colors: [
                        .black.opacity(0.03), .black.opacity(0.12),
                        .black.opacity(0.74)
                    ], startPoint: .top, endPoint: .bottom
                )

                HStack(alignment: .bottom, spacing: 6) {
                    Image(systemName: activity.icon)
                        .font(.system(size: 16, weight: .semibold))
                    Text(activity.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(11)
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.title)
        .accessibilityHint(tr(
            "Open workout setup", "Åpner treningsoppsett"
        ))
    }

    private var ghostRaceSection: some View {
        Button(action: onGhostRace) {
            ZStack(alignment: .leading) {
                GeometryReader { imageGeometry in
                    Image("GoalRunning")
                        .resizable()
                        .scaledToFill()
                        .saturation(0.25)
                        .frame(
                            width: imageGeometry.size.width,
                            height: 79
                        )
                        .clipped()
                        .allowsHitTesting(false)
                }
                .frame(height: 79)
                .allowsHitTesting(false)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.69),
                        Color.black.opacity(0.43)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
                HStack(spacing: 13) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ghost Race")
                            .font(.system(size: 17, weight: .medium, design: .serif))
                        Text(tr("Race your previous results", "Tren mot dine tidligere tider"))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(15)
            }
            .frame(height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activePlanSection(_ plan: TrainingPlan) -> some View {
        Button(action: onOpenPlan) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(champagne)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("ACTIVE PLAN", "AKTIV PLAN"))
                            .font(.caption2.weight(.semibold))
                            .tracking(1.15)
                            .foregroundStyle(muted)
                        Text(plan.title)
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(planPosition)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink)
                }

                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(hairline.opacity(0.52))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(champagne)
                                    .frame(
                                        width: geometry.size.width
                                            * min(max(completionFraction, 0), 1)
                                    )
                            }
                    }
                    .frame(height: 5)
                    Text("\(Int((min(max(completionFraction, 0), 1) * 100).rounded())) %")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(muted)
                }
            }
            .padding(15)
            .premiumTrainSurface(line: hairline)
        }
        .buttonStyle(.plain)
    }

    private func detailLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 15)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutImage(for kind: WorkoutKind) -> String {
        switch kind {
        case .strength: return "StrengthQuickHero"
        case .running: return "GoalRunning"
        case .walking: return "GoalWalking"
        case .recovery, .mobility: return "GoalRecovery"
        case .custom: return "TrainHero"
        }
    }

    private func tr(_ english: String, _ norwegian: String) -> String {
        ATHLTHLocalization.choose(english: english, norwegian: norwegian)
    }
}

private extension View {
    func premiumTrainSurface(line: Color) -> some View {
        self
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(line.opacity(0.68), lineWidth: 0.7)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 5)
    }
}


/// Pure, deterministic selection for Train discovery. No user profiling,
/// hidden AI prescriptions or dependence on network availability.
enum TrainWorkoutSuggestionPolicy {
    static func pick(
        _ entries: [WorkoutTemplateCatalogEntry],
        preferredKind: WorkoutKind?
    ) -> [WorkoutTemplateCatalogEntry] {
        let safe = entries.filter { entry in
            !entry.blocks.isEmpty &&
            !["Advanced", "Avansert"].contains(where: {
                entry.difficulty.localizedCaseInsensitiveCompare($0) == .orderedSame
            }) &&
            !entry.tags.contains(where: { $0.localizedCaseInsensitiveContains("hyrox") })
        }.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        guard !safe.isEmpty else { return [] }

        let category: String?
        switch preferredKind {
        case .running: category = "running"
        case .walking: category = "walking"
        case .strength: category = "strength"
        default: category = nil
        }

        var ordered = safe
        if let category {
            let matched = safe.filter { $0.category == category }
            let remaining = safe.filter { $0.category != category }
            ordered = matched + remaining
        } else {
            let entryLevel = safe.filter { entry in
                ["Beginner", "Nybegynner", "All levels", "Alle nivåer"].contains { level in
                    entry.difficulty.localizedCaseInsensitiveCompare(level) == .orderedSame
                }
            }
            if !entryLevel.isEmpty {
                let other = safe.filter { entry in !entryLevel.contains(where: { $0.id == entry.id }) }
                ordered = entryLevel + other
            }
        }

        guard let first = ordered.first else { return [] }
        var picked = [first]
        if let different = ordered.dropFirst().first(where: {
            $0.category != first.category
        }) {
            picked.append(different)
        } else if let second = ordered.dropFirst().first {
            picked.append(second)
        }
        return picked
    }
}

/// Never infer a rest prescription from an empty calendar. HealthKit recovery
/// is informational only when a complete recent baseline is available.
enum TrainTodayOverviewPolicy {
    enum Status: Equatable {
        case noActivePlan
        case noWorkoutInPlan
        case trainedToday
    }

    static func status(
        hasPlan: Bool,
        hasRecordedWorkoutToday: Bool
    ) -> Status {
        if hasRecordedWorkoutToday { return .trainedToday }
        return hasPlan ? .noWorkoutInPlan : .noActivePlan
    }

    /// A completed iPhone workout still counts when HealthKit access is denied
    /// or its import has not finished. Never count an active, unfinished session.
    static func hasRecordedWorkout(
        on day: Date,
        healthStartDates: [Date],
        strengthEndDates: [Date],
        phoneCompletedDates: [Date],
        calendar: Calendar = .current
    ) -> Bool {
        healthStartDates.contains { calendar.isDate($0, inSameDayAs: day) } ||
            strengthEndDates.contains { calendar.isDate($0, inSameDayAs: day) } ||
            phoneCompletedDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    static func reliableReadiness(
        _ readiness: RecoveryReadinessSummary,
        sleepEnd: Date?,
        hrvDate: Date?,
        restingHeartRateDate: Date?,
        now: Date = Date()
    ) -> RecoveryReadinessSummary? {
        guard readiness.baselineDays >= 5,
              readiness.score != nil,
              readiness.state != .buildingBaseline,
              let sleepEnd,
              let hrvDate,
              let restingHeartRateDate else {
            return nil
        }

        let fresh = [sleepEnd, hrvDate, restingHeartRateDate].allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= 0 && age <= 48 * 3600
        }
        return fresh ? readiness : nil
    }
}